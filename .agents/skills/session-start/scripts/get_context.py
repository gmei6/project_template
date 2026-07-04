import os
import sys

def read_file(filepath):
    if not os.path.exists(filepath):
        return None
    with open(filepath, 'r') as f:
        return f.read().strip()

def main():
    files_to_read = [
        "AGENTS.md",
        "okf/index.md",
        "okf/status.md",
        "okf/next-actions.md",
        "okf/open-questions.md"
    ]
    
    output = []
    for filepath in files_to_read:
        content = read_file(filepath)
        if content:
            output.append(f"=== {filepath} ===")
            output.append(content)
            output.append("")
    
    if not output:
        print("No OKF context files found.")
    else:
        print("\n".join(output))

if __name__ == "__main__":
    main()
