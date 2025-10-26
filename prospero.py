# ==========================
# Configuration
# ==========================

IMAGE_SIZE = 128  # Size of the image (width and height)
SPACE = []
for i in range(IMAGE_SIZE):
    value = -1 + 2 * i / (IMAGE_SIZE - 1)
    SPACE.append(value)


# ==========================
# Coordinate Grid Creation
# ==========================

GRID_X = []
GRID_Y = []
for i in range(IMAGE_SIZE):
    x_row = []
    y_row = []
    for j in range(IMAGE_SIZE):
        x_row.append(SPACE[j])     # horizontal coordinate
        y_row.append(-SPACE[i])    # vertical coordinate
    GRID_X.append(x_row)
    GRID_Y.append(y_row)



# ==========================
# Helper Functions
# ==========================

def apply_binary_operation(array_a, array_b, operation):
    """
    Apply a binary operation element-wise between two 2D arrays.
    """
    result = []
    for i in range(IMAGE_SIZE):
        row = []
        for j in range(IMAGE_SIZE):
            value = operation(array_a[i][j], array_b[i][j])
            row.append(value)
        result.append(row)
    return result


def apply_unary_operation(array_a, operation):
    """
    Apply a unary operation element-wise to a 2D array.
    """
    result = []
    for i in range(IMAGE_SIZE):
        row = []
        for j in range(IMAGE_SIZE):
            value = operation(array_a[i][j])
            row.append(value)
        row = list(row)
        result.append(row)
    return result


# ==========================
# VM Execution
# ==========================

variables = {}
last_variable_name = None

with open("prospero.vm", "r", encoding="utf-8") as file:
    for raw_line in file:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        parts = line.split()
        out_name = parts[0]
        opcode = parts[1]
        args = parts[2:]
        last_variable_name = out_name

        if opcode == "var-x":
            variables[out_name] = GRID_X

        elif opcode == "var-y":
            variables[out_name] = GRID_Y

        elif opcode == "const":
            constant_value = float(args[0])
            const_array = []
            for _ in range(IMAGE_SIZE):
                const_array.append([constant_value] * IMAGE_SIZE)
            variables[out_name] = const_array

        elif opcode == "add":
            variables[out_name] = apply_binary_operation(
                variables[args[0]], variables[args[1]], lambda a, b: a + b
            )

        elif opcode == "sub":
            variables[out_name] = apply_binary_operation(
                variables[args[0]], variables[args[1]], lambda a, b: a - b
            )

        elif opcode == "mul":
            variables[out_name] = apply_binary_operation(
                variables[args[0]], variables[args[1]], lambda a, b: a * b
            )

        elif opcode == "max":
            variables[out_name] = apply_binary_operation(
                variables[args[0]], variables[args[1]], lambda a, b: a if a > b else b
            )

        elif opcode == "min":
            variables[out_name] = apply_binary_operation(
                variables[args[0]], variables[args[1]], lambda a, b: a if a < b else b
            )

        elif opcode == "neg":
            variables[out_name] = apply_unary_operation(
                variables[args[0]], lambda a: -a
            )

        elif opcode == "square":
            variables[out_name] = apply_unary_operation(
                variables[args[0]], lambda a: a * a
            )

        elif opcode == "sqrt":
            variables[out_name] = apply_unary_operation(
                variables[args[0]], lambda a: a**0.5 if a >= 0 else float("nan")
            )

        else:
            raise ValueError(f"Unknown opcode: {opcode}")

if last_variable_name is None:
    raise RuntimeError("The VM file contained no executable instructions.")

# ==========================
# Image Output (PGM)
# ==========================

output_array = variables[last_variable_name]

with open("output_ascii.pgm", "w", encoding="ascii") as f:
    # Header for ASCII PGM
    f.write(f"P2\n{IMAGE_SIZE} {IMAGE_SIZE}\n255\n")

    for i in range(IMAGE_SIZE):
        row_values = []
        for j in range(IMAGE_SIZE):
            value = output_array[i][j]
            pixel_value = 255 if (isinstance(value, float) and value < 0) else 0
            row_values.append(str(pixel_value))
        # Write one row of pixel values separated by spaces
        f.write(" ".join(row_values) + "\n")

print("✅ ASCII PGM written to 'output_ascii.pgm'")



# from https://www.mattkeeter.com/projects/prospero/

# import numpy as np

# with open('prospero.vm') as f:
#     text = f.read().strip()

# image_size = 1024
# space = np.linspace(-1, 1, image_size)
# (x, y) = np.meshgrid(space, -space)
# v = {}

# for line in text.split('\n'):
#     if line.startswith('#'):
#         continue
#     [out, op, *args] = line.split()
#     match op:
#         case "var-x": v[out] = x
#         case "var-y": v[out] = y
#         case "const": v[out] = float(args[0])
#         case "add": v[out] = v[args[0]] + v[args[1]]
#         case "sub": v[out] = v[args[0]] - v[args[1]]
#         case "mul": v[out] = v[args[0]] * v[args[1]]
#         case "max": v[out] = np.maximum(v[args[0]], v[args[1]])
#         case "min": v[out] = np.minimum(v[args[0]], v[args[1]])
#         case "neg": v[out] = -v[args[0]]
#         case "square": v[out] = v[args[0]] * v[args[0]]
#         case "sqrt": v[out] = np.sqrt(v[args[0]])
#         case _: raise Exception(f"unknown opcode '{op}'")
# out = v[out]

# with open('out.ppm', 'wb') as f: # write the image out
#     f.write(f'P5\n{image_size} {image_size}\n255\n'.encode())
#     f.write(((out < 0) * 255).astype(np.uint8).tobytes())


