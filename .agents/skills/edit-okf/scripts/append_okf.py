import sys
import os

def append_to_file(filepath, content):
    os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)
    
    # Check if file exists and has content to manage newlines
    needs_newline = False
    file_exists = os.path.exists(filepath)
    if file_exists and os.path.getsize(filepath) > 0:
        with open(filepath, 'rb') as f:
            f.seek(-1, os.SEEK_END)
            if f.read(1) != b'\n':
                needs_newline = True
                
    if file_exists:
        os.chmod(filepath, 0o644)
        
    try:
        with open(filepath, 'a') as f:
            if needs_newline:
                f.write('\n')
            f.write(content)
            if not content.endswith('\n'):
                f.write('\n')
    finally:
        if os.path.exists(filepath):
            os.chmod(filepath, 0o444)
            
    print(f"Successfully appended content to {filepath}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python append_okf.py <filepath> [content]")
        print("If content is not provided, reads from stdin.")
        sys.exit(1)
        
    filepath = sys.argv[1]
    
    if len(sys.argv) >= 3:
        content = sys.argv[2]
    else:
        content = sys.stdin.read()
        
    append_to_file(filepath, content)

if __name__ == "__main__":
    main()
