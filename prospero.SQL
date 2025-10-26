-- Background: https://www.mattkeeter.com/projects/prospero/ 

-- Total running time for one point - 35 minutes 


/* Steps to solve the problem in SQL

1. Define the image size, 128 
2. From -1 to 1, evenly distribute the 128 numbers
3. Generate a grid, from (-1,-1) to (1,1), Total cell number is 128*128 
4. For each point in the panel, assign the value, based on the calculation on step 2 
   4.1 from left to right, the number is -1 to 1 
   4.2 from up to down, the number is 1 to -1
   4.3 for each point, there should be 2 numbers, one is from X-axis, one is from Y-axis. These 2 numbers will be used for calculation later
5. For each point in the panel, go through the whole prospero instruction, get the result
    -- All the operations will have step_id, operation, op1, op2 and result
    -- Concatenate the entire prospero instruction as a string , each step delimited with `, and for each step, step id, operand, and result are delimited with |
    -- For the current step, unpack the concat string, get the current step 
    -- Get the op1 and op2, if it's a reference to the previous step, get the result of the corresponding step, with prospero_get_step_res
    -- Compute current operation
    -- Update the concatenated string, this string will be used for next iteration in the recursive CTE
    -- Get the result with step_id = total_count-1 from the prospero table

6. The final result will be either 0 or 1 for each point
    -- 1 if the computed final result is < 0 
    -- 0 if the computed final resilt is >= 0

7. Generate the final output


Takeaways - 

1. In order for the recursive CTE to preserve the previous iteration result, a string is used and updated for each iteration, and the string is then passed to the next iteration
2. SQL Server will not allow select from a temp table in the cross apply part.
3. Instead of using a lot of cross apply and recursive CTEs - put the reusable part into a function to make the code cleaner 
4. Using a wrap function to wrap the compute and update process. So for each point, we can retrive the final output by just calling the wrapper function


*/

-- clean up the table for the ones imported with scientific notion

--select * from prospero_instruction 
--where op1 like '%e[+-]%' or op2 like '%e[+-]%'

--update prospero_instruction set op1 = '100000000'
--where step = '_1134'

--update prospero_instruction set op1 = cast( cast( 4.76837 /  power(10, 7) as decimal(38,10)) as varchar(100))
--where step = '_1069'



drop table if exists #tmp_space

; with cte as 
(select loc = cast(-1 as decimal(38,10)), iter = 1, starting = -1, ending = 1, total_cnt = 128.0
union all 
select loc = cast(-1 + (ending-starting) * ( iter / (total_cnt - 1))  as decimal(38,10))
, iter+1
, starting
, ending
, total_cnt  
 from cte 
where iter <= total_cnt-1
)
select * into #tmp_space
 from cte 
option (maxrecursion 0)

--for grid_x , it's just repeat the numbers for each row
drop table if exists #grid_x

; with cte_grid_x as 
(
    select col = iter, row = 1, val = loc, total_cnt from #tmp_space
    union all 
    select col, row + 1, val, total_cnt from cte_grid_x
    where row < total_cnt 
) 
select * into #grid_x from cte_grid_x 
option (maxrecursion 0)

-- for grid_y, it's a transpose of the space array, and repeat for 128 times

drop table if exists #grid_y

; with cte_grid_y as 
(
select 
row = col 
, col = row  -- row becomes column
, val 
, total_cnt 
from #grid_x
where col = 1 

union all 

select
curr.row+1
, col = x.row
, x.val
, x.total_cnt
from cte_grid_y curr 
inner join #grid_x x on x.col = curr.row + 1 and x.row = curr.col
)
select * into #grid_y from cte_grid_y 
option (maxrecursion 0 )



drop table if exists #grid 

select 
rn = ROW_NUMBER() over(order by x.[row], x.col )
, 
x.[row], x.col, x = x.val, y = y.val 
into #grid
from #grid_x x inner join #grid_y y 
on x.[row] = y.[row] and x.col = y.col


drop table if exists #prospero

select 
step_id  = cast(CONVERT(varbinary, step_padded ,2) as int )
, step
, op = [action] 
, op1 = case when op1 = 'NULL' then '' else op1 end
, op2 = case when op2 = 'NULL' then '' else op2 end
, res
into #prospero
from prospero_instruction
cross apply (select step_cleaned =  upper(REPLACE(step, '_', '') ) ) _
cross apply (select step_padded = case when len(step_cleaned) % 2 = 0 then step_cleaned else '0' + step_cleaned end) __



go 


create or alter function prospero_get_step_res(@concated varchar(max), @step varchar(100))
returns table 
as 
return 

select res = res.val from 
    (select op_by_step = value from string_split(@concated, '`') ) ap1  
    outer apply  
    (select val from prospero_string_split(ap1.op_by_step, '|', 1) where id = 5) res
where op_by_step like @step + '|%'

go 



------------ Testing code for prospero_get_step_res ------------
; with cte as 
(
select 
n = STRING_AGG( cast( CONCAT_WS('|', cast(step_id as varchar) , op, op1, op2, isnull(res, 'NULL')) as varchar(max)), '`') 
within group(order by step_id) 
, x= 1
, y = 1 
from #prospero, #grid 
where col = 1 and row = 1  -- x = 1, y = 1
) 
select ap1.* from cte cross apply 
    (select * from prospero_get_step_res(n, 1)) ap1



go 

 

create or alter function prospero_update_step_res(@concat varchar(max), @step varchar(100), @res_val varchar(100))
returns table 
as 
return 
with cte as (
select 
op_by_step 
, step_res = string_agg(res.val , '|') within group (order by id)
from 
    (select op_by_step = value from string_split(@concat, '`')) ap1  -- split the string into steps
    cross apply  
    (
	 select id, val from prospero_string_split( ap1.op_by_step, '|', 1) where id != 5 -- for the target step, split into op, op1, op2... 
		union
	 select 5, @res_val	-- put the value to the spot, the result value is on 5th column
	) res
where op_by_step like @step+ '|%'
group by op_by_step
)
select 
updated_res = stuff(@concat -- the original string
				  , charindex('`' + @step+ '|' , @concat)+1 -- starting from this node position
				  , len(op_by_step)  -- the node string length
				  , step_res  --concated the updated node string 
				  )
from cte

go 


------------ Testing code for prospero_update_step_res ------------
; with cte as 
(
select 
n = STRING_AGG( cast( CONCAT_WS('|', cast(step_id as varchar), isnull(op, ''), isnull(op1,''), isnull(op2, ''), isnull(res, '')) as varchar(max)), '`') 
within group(order by step_id) 
, x = 1
, y = 1 
from #prospero, #grid 
where col = 1 and row = 1  -- x = 1, y = 1
)   
select ap1.* from cte cross apply 
    (select * from prospero_update_step_res(n, 2, 1000)) ap1



go 






create or alter function prospero_compute_step(@concat varchar(max), @step varchar(100), @x varchar(100), @y varchar(100))
returns table 
as return 
select
step_id = step_id.val
, op = op.val
, op1_base = op1_base.val 
, op2_base = op2_base.val
, op1_ref = op1_ref.op1
, op2_ref = op2_ref.op2
, op1 = op1_final.op1 
, op2 = op2_final.op2 
, res =  case when op.val ='const' then op1_final.op1
              when op.val = 'add' then op1_final.op1 + op2_final.op2 
              when op.val = 'max' then iif(op1_final.op1 >= op2_final.op2, op1_final.op1, op2_final.op2)
              when op.val = 'min' then iif(op1_final.op1 <= op2_final.op2, op1_final.op1, op2_final.op2) 
              when op.val = 'mul' then op1_final.op1 * op2_final.op2
              when op.val = 'neg' then -op1_final.op1
              when op.val = 'sqrt' then power(op1_final.op1, 0.5)
              when op.val = 'square' then power(op1_final.op1,  2)
              when op.val = 'sub' then op1_final.op1 - op2_final.op2
              when op.val = 'var-x' then cast(@x as decimal(38, 10))
              when op.val = 'var-y' then cast(@y as decimal(38, 10))
              else -999999999
            end

from 
    (select step_op = value from string_split(@concat, '`') ) ap1  
    cross apply  
    (select val from prospero_string_split(ap1.step_op, '|', 1) where id = 1) step_id
    cross apply  
    (select val from prospero_string_split(ap1.step_op, '|', 1) where id = 2) op
    outer apply  -- using outapply in case op1 does not exist
    (select val from prospero_string_split(ap1.step_op, '|', 1) where id = 3) op1_base
	outer apply
	(select op1 = case when isnull(op1_base.val, '') not like '`_%' escape '`' then cast(op1_base.val as decimal(38, 10)) -- if it's not a reference
					   else (
							 select res from prospero_get_step_res(@concat
																	, 
																  (cast( convert( varbinary, iif( len(op1_base.val) % 2 = 1, '', '0') + replace(op1_base.val, '_', ''), 2) as int)) 
																  )-- if it's a reference, get the res from the @concat
						    )
					   end 			
     ) op1_ref
	outer apply
	(select op1 = cast(op1_ref.op1 as decimal(38, 10))) op1_final
    outer apply  
    (select val from prospero_string_split(ap1.step_op, '|', 1) where id = 4) op2_base 
	outer apply  -- using outapply in case op2 does not exist
	(select op2 = case when isnull(op2_base.val, '') not like '`_%' escape '`' then cast(op2_base.val as decimal(38, 10))-- if it's not a reference
					   else (
							 select res from prospero_get_step_res(@concat
																	, 
																  (cast( convert( varbinary, iif( len(op2_base.val) % 2 = 1, '', '0') + replace(op2_base.val, '_', ''), 2) as int)) 
																  )-- if it's a reference, get the res from the @concat
						    )
					   end 			
     ) op2_ref
	outer apply 
	(select op2 =cast(op2_ref.op2 as decimal(38, 10))) op2_final

where ap1.step_op like @step  + '|%' 




go 


------------ Testing code for prospero_compute_step ------------

; with cte as 
(
select 
n = STRING_AGG( cast( CONCAT_WS('|', cast(step_id as varchar) , op, op1, op2, isnull(res, '')) as varchar(max)), '`') 
within group(order by step_id) 
, x= 1
, y = 1 
from #prospero, #grid 
where col = 1 and row = 1  -- x = 1, y = 1
) 
select * from cte cross apply 
	-- (select step_op = value from string_split(n, '`') ) ap0  outer apply 
    (select * from prospero_compute_step(n, 1, x, y)) ap1

-- commit 

-- select * from #step_lookup 

-- select * from #prospero
-- where step_id between 4403 and 4406

--select op , * from #prospero 
--where op = 'sqrt'
--order by 1 

--select distinct op from #prospero 
--order by 1 



-- select * from #prospero 
-- order by 1 



-- prospero_compute_step 
-- prospero_get_step_res
-- prospero_update_step_res


go


create or alter function prospero_wrap(@concat varchar(max), @total_iter int,   @x varchar(max),  @y varchar(max))
returns table 
as 
return 

with cte as 
(
select 
curr_step = 0
, res = @concat 

union all 

select curr_step + 1 
, updated.updated_res
from cte
	cross apply (select comp_res = res from prospero_compute_step(res, cast(curr_step as int), @x, @y) ) comp
	cross apply (select updated_res from prospero_update_step_res(res, cast(curr_step as int), comp_res ) ) updated
where curr_step <= @total_iter
) 
select 
* 
from cte
where curr_step = @total_iter 



go 


--



--------------------------------------------------------
--------------------------------------------------------
--------------------------------------------------------
--------------------------------------------------------

drop table if exists #res

; with cte as 
(
	select 
      rn
	, x
	, y 
	from #grid 
	-- where rn = 1  
) 
select 
rn
, x
, y
, ans = (select res from prospero_get_step_res (curr.res, (select count(*)-1 from #prospero) ))
into #res
from cte cross apply 
	(select res from prospero_wrap( 
							  (select STRING_AGG( cast( CONCAT_WS('|', cast(step_id as varchar) , isnull(op, ''), isnull(op1, ''), isnull(op2, ''), isnull(res, '')) as varchar(max)), '`')  within group(order by step_id) from #prospero ) --  where step_id between 0 and 100) -- concated operation string
							, (select count(*) from #prospero) -- total iteration times
							, x -- current x
							, y -- current y
							)
	) curr  
option (maxrecursion 0)



select
STRING_AGG(cast(case when ans < 0 then 1 else 0 end as varchar(max)), '') within group(order by rn)
from #res 
group by rn / 128








-- ######################################################################################
-- ##########Below are testing code ##################
-- ######################################################################################

-- ; with a as 
-- (select 1 id, t = '*'
-- UNION ALL
-- select id + 1, t from a
-- where id < 128*128
-- )
-- select STRING_AGG(t, '') within GROUP(order by id ) from a
-- group by id /128 
-- OPTION(maxrecursion 0 )



-- select 
-- 128*128* len((select STRING_AGG( cast( CONCAT_WS('|', cast(step_id as varchar) , isnull(op, ''), isnull(op1, ''), isnull(op2, ''), isnull(res, '')) as varchar(max)), '`')  within group(order by step_id) from #prospero ))
-- /1000/1000.0
-- -- where step_id <= 0) -- concated operation string)

-- --prospero_update_step_res(@concat varchar(max), @step varchar(100), @res_val varchar(100))


-- --goprospero_compute_step
 

-- (
-- select STRING_AGG( cast( CONCAT_WS('|', cast(step_id as varchar) , isnull(op, ''), isnull(op1, ''), isnull(op2, ''), isnull(res, '')) as varchar(max)), '`') 
-- within group(order by step_id) from #prospero
-- )
--  --  (select step_op = value from string_split(n, '`') ) ap1  
--  --   cross apply  
--  --   (select val from prospero_string_split(ap1.step_op, '|', 1) where id = 1) step_id
--  --   cross apply  
--  --   (select val from prospero_string_split(ap1.step_op, '|', 1) where id = 2) op
--  --   outer apply  -- using outapply in case op1 does not exist
--  --   (select val from prospero_string_split(ap1.step_op, '|', 1) where id = 3) op1_base
-- 	--outer apply
-- 	--(select 
						   
-- 	--	op0 =   cast( case when isnull(op1_base.val, '') not like '`_%' escape '`' then op1_base.val -- if it's not a reference
-- 	--				   else 					   
-- 	--				    iif( len(op1_base.val) % 2 = 1, '', '0') + replace(op1_base.val, '_', '')
			   
-- 	--			end as varchar(max))
-- 	--		, turn = case when isnull(op1_base.val, '') like '`_%' escape '`' then 1 else 0  end 
-- 	--) op_t
-- 	--outer apply
-- 	--(select 
-- 	-- op_final = case when turn = 1 then try_cast( try_cast(TRY_CONVERT(varbinary, op0, 2) as int) as decimal(38, 10))
-- 	--			else cast(op0 as decimal(38, 10)) end 
-- 	-- ) op_ref 

