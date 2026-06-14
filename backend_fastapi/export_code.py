import os

# In folders aur files ko hum ignore karenge taaki kachra na aaye
IGNORE_DIRS = {'venv', '.git', '__pycache__', 'uploads', 'data', '__builtins__'}
IGNORE_EXTS = {'.db', '.pyc', '.png', '.jpg', '.jpeg', '.txt'}

with open("backend_context.txt", "w", encoding="utf-8") as out:
    out.write("=== 📂 DIRECTORY STRUCTURE ===\n")
    for root, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in IGNORE_DIRS]
        level = root.replace(".", "").count(os.sep)
        indent = " " * 4 * level
        out.write(f"{indent}{os.path.basename(root)}/\n")
        subindent = " " * 4 * (level + 1)
        for f in files:
            if not any(f.endswith(ext) for ext in IGNORE_EXTS) and f != "export_code.py":
                out.write(f"{subindent}{f}\n")

    out.write("\n\n=== 📝 FILE CONTENTS ===\n")
    for root, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in IGNORE_DIRS]
        for f in files:
            if f.endswith('.py') and f != "export_code.py":
                filepath = os.path.join(root, f)
                out.write(f"\n\n{'='*60}\nFILE: {filepath}\n{'='*60}\n\n")
                try:
                    with open(filepath, "r", encoding="utf-8") as infile:
                        out.write(infile.read())
                except Exception as e:
                    out.write(f"Error reading file: {e}")

print("✅ BOOM! Context is successfully saved in 'backend_context.txt'")