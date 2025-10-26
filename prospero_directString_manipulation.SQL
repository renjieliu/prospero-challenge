-- Background: https://www.mattkeeter.com/projects/prospero/ 

-- Total running time for one point - 4 minutes 

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
; 

-- with cte as (
--     select concat_json = 
--         ( 
--             select step_id, step, op, op1, op2, res from #prospero 
--             -- where cast(step_id as int) < 10
--             for json path 
--         )
-- )
-- select 
-- *
--  from openjson( (select * from cte) ) 
--  WITH (
--   step_id int
--   , step varchar(max)
--   , op varchar(max)
--   , op1 varchar(max) 
--   , op2 varchar(max) 
--   , res varchar(max)
-- )
-- WHERE step_id = 2192;


go 

-- SELECT *
-- FROM OPENJSON(@json)
-- WITH (
--     step_id INT,
--     step_name NVARCHAR(100),
--     step_status NVARCHAR(50)
-- )
-- WHERE step_id = 2;

go


create or alter function prospero_string_get_step_items(
        @concat varchar(max)
        , @step_id varchar(100)
        , @col int -- which column to get 
        , @width int)
returns varchar(100) 
as 
begin
declare @res varchar(100)

select 
@res = SUBSTRING(@concat
                , @width * @step_id * 5 + @step_id * 4 + @step_id  -- text length for each step + 5 delimiters (|) + separators b/w steps (`)
                + @width * (@col-1) + (@col-1) + 1   -- current step previous column length + delimiter (|) and skip the current delimiter
                , @width)

return @res

end


go 



------------ Testing code for prospero_json_get_step_res ------------



--; with cte as 
--(
--select concat = STRING_AGG(cast(
--                    CONCAT_WS('|', cast(step_id as varchar) + space(30 - len (cast(step_id as varchar) ))
--                            , isnull(op, '') + space(30 - len (isnull(op, '')))
--                            , isnull(op1, '')+ space(30 - len (isnull(op1, '') ))
--                            , isnull(op2, '')+ space(30 - len (isnull(op2, '') ))
--                            , isnull(res, '')+ space(30 - len (isnull(res, '') ))
--                            ) 
--                            as varchar(max)), '`') 
--                     within group(order by step_id) 
        
--from #prospero
--) -- select * from cte
--select ap1.* from cte cross apply (select res = dbo.prospero_string_get_step_items(concat, 5, 5, 30) ) ap1



go 

 

create or alter function prospero_string_update_step_res(@concat varchar(max), @step_id varchar(100), @res_val varchar(100), @width int )
returns varchar(max) 
as 
begin 

declare @res varchar(max)

select @res = STUFF(@concat
                    , @width * @step_id * 5 + @step_id * 4 + @step_id  -- text length for each step + 5 delimiters (|) + separators b/w steps (`)
                     + @width * 4 + 4 + 1   -- current step previous column length + delimiter (|) and skip the current delimiter
                    , @width
                    , isnull(@res_val, '') + space(@width - len(isnull(@res_val, ''))) -- padding spaces
                    )
    
 return @res 

end

 
go 


------------ Testing code for prospero_json_update_step_res ------------


--; with cte as 
--(
--select concat = STRING_AGG(cast(
--                    CONCAT_WS('|', cast(step_id as varchar) + space(30 - len (cast(step_id as varchar) ))
--                            , isnull(op, '') + space(30 - len (isnull(op, '')))
--                            , isnull(op1, '')+ space(30 - len (isnull(op1, '') ))
--                            , isnull(op2, '')+ space(30 - len (isnull(op2, '') ))
--                            , isnull(res, '')+ space(30 - len (isnull(res, '') ))
--                            ) 
--                            as varchar(max)), '`') 
--                     within group(order by step_id) 
        
--from #prospero
--) -- select * from cte
--select ap1.* from cte cross apply (select res = dbo.prospero_string_update_step_res(concat, 7, 6.23111,  30) ) ap1


go 






create or alter function prospero_string_compute_step(
      @concat varchar(max)
    , @step_id varchar(100)
    , @x varchar(100)
    , @y varchar(100)
    , @width int)
returns decimal(38, 10)
as
begin 

declare @res decimal(38, 10)

; with cte as
(
    select 
    step_id = rtrim(dbo.prospero_string_get_step_items(@concat, @step_id, 1, 30))
    , op  = rtrim(dbo.prospero_string_get_step_items(@concat,  @step_id, 2, 30))
    , op1  = rtrim(dbo.prospero_string_get_step_items(@concat, @step_id, 3, 30))
    , op2  = rtrim(dbo.prospero_string_get_step_items(@concat, @step_id, 4, 30))
    , res  = rtrim(dbo.prospero_string_get_step_items(@concat, @step_id, 5, 30)) 
)
, staging as (
select
step_id
, op
, op1 = case when left(isnull(op1, ''), 1) <> '_' then try_cast(op1 as decimal(38, 10)) -- if it's not a reference
             else rtrim(dbo.prospero_string_get_step_items(@concat, cast(ap1.conv as int), 5, 30)) -- if it's a reference, get the res from the unpacked JSON
		    end 

, op2 = case when left(isnull(op2, ''), 1) <> '_' then try_cast(op2 as decimal(38, 10)) -- if it's not a reference
             else rtrim(dbo.prospero_string_get_step_items(@concat, cast(ap2.conv as int), 5, 30)) -- if it's a reference, get the res from the unpacked JSON
		    end 
, res
from cte 
cross apply (select conv = convert(varbinary
										, iif( len( case when left(op1, 1 ) = '_' then op1 else NULL end) % 2 = 1, '', '0')
										  + 
										  replace( case when left(op1, 1 ) = '_' then op1 else NULL end , '_', '')
										, 2) 
			) ap1
cross apply (select conv = convert(varbinary
										, iif( len( case when left(op2, 1 ) = '_' then op2 else NULL end) % 2 = 1, '', '0')
										  + 
										  replace( case when left(op2, 1 ) = '_' then op2 else NULL end , '_', '')
										, 2) 
			) ap2 
)
select @res =  case when op ='const' then op1
                    when op = 'add' then op1 + op2 
                    when op = 'max' then iif( op1 >= op2,  op1, op2)
                    when op = 'min' then iif( op1 <= op2, op1, op2) 
                    when op = 'mul' then op1 *  op2
                    when op = 'neg' then -op1
                    when op = 'sqrt' then power(op1, 0.5)
                    when op = 'square' then power(op1,  2)
                    when op = 'sub' then op1 - op2
                    when op = 'var-x' then cast(@x as decimal(38, 10))
                    when op = 'var-y' then cast(@y as decimal(38, 10))
                  else -999999999
                end
    from staging
    where step_id = @step_id

return @res

end

go 


------------ Testing code for prospero_json_compute_step ------------



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





--; with cte as 
--(
--select concated = STRING_AGG(cast(
--                    CONCAT_WS('|', cast(step_id as varchar) + space(30 - len (cast(step_id as varchar) ))
--                            , isnull(op, '') + space(30 - len (isnull(op, '')))
--                            , isnull(op1, '')+ space(30 - len (isnull(op1, '') ))
--                            , isnull(op2, '')+ space(30 - len (isnull(op2, '') ))
--                            , isnull(res, '')+ space(30 - len (isnull(res, '') ))
--                            ) 
--                            as varchar(max)), '`') 
--                     within group(order by step_id) 
        
--from #prospero
--) 
--select ap1.* from cte cross apply
--(select res=dbo.prospero_string_compute_step(concated, 1, 1, 1, 30)) ap1
 


go


create or alter function prospero_string_wrap (@concat varchar(max), @total_iter int,   @x varchar(max),  @y varchar(max), @width int)
returns table  
as 
return

with cte as 
(
select 
step_id = 0
, res = @concat 

union all 

select 
step_id + 1
, updated.updated_res
from cte
	cross apply (select comp_res = dbo.prospero_string_compute_step(res, cast(step_id as int), @x, @y, @width)) comp
	cross apply (select updated_res = dbo.prospero_string_update_step_res(res, cast(step_id as int), comp_res, @width)) updated
where step_id <= @total_iter
) 
select 
* 
from cte
where step_id = @total_iter 



go 



; with cte as 
(
select concated = STRING_AGG(cast(
                    CONCAT_WS('|', cast(step_id as varchar) + space(30 - len (cast(step_id as varchar) ))
                            , isnull(op, '') + space(30 - len (isnull(op, '')))
                            , isnull(op1, '')+ space(30 - len (isnull(op1, '') ))
                            , isnull(op2, '')+ space(30 - len (isnull(op2, '') ))
                            , isnull(res, '')+ space(30 - len (isnull(res, '') ))
                            ) 
                            as varchar(max)), '`') 
                     within group(order by step_id) 
        
from #prospero
) 
select ap1.* from cte cross apply (select * from dbo.prospero_string_wrap(concated, 30, 1, 1, 30)) ap1
 


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
	where rn = 1  -- how many points to be iterated
), cte_concat as 
(
select concated = STRING_AGG(cast(
                    CONCAT_WS('|', cast(step_id as varchar) + space(30 - len (cast(step_id as varchar) ))
                            , isnull(op, '') + space(30 - len (isnull(op, '')))
                            , isnull(op1, '')+ space(30 - len (isnull(op1, '') ))
                            , isnull(op2, '')+ space(30 - len (isnull(op2, '') ))
                            , isnull(res, '')+ space(30 - len (isnull(res, '') ))
                            ) 
                            as varchar(max)), '`') 
                     within group(order by step_id) 
from #prospero
)
select 
rn
, x
, y
, ans = (select res = dbo.prospero_string_get_step_items(curr.res, (select count(*)-1 from #prospero), 5, 30))
into #res
from cte cross apply 
	(select res from prospero_string_wrap( 
							(select concated  from cte_concat)   --  where step_id between 0 and 100) -- concated operation string
							, (select count(*) from #prospero) -- total iteration times
							, x -- current x
							, y -- current y
							, 30 -- width
							)
	) curr  
option (maxrecursion 0)



select
* 
--STRING_AGG(cast(case when ans < 0 then 1 else 0 end as varchar(max)), '') within group(order by rn)
from #res 
-- group by rn / 128








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

