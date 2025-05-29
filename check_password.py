import bcrypt
import base64
import sys

def check_password_file(file_path):
    try:
        with open(file_path, 'r') as f:
            content = f.read().strip()
        
        # Try to decode the base64 content
        try:
            decoded = base64.b64decode(content)
            print("✓ Base64 decoding successful")
            print(f"Length of decoded data: {len(decoded)} bytes")
        except:
            print("✗ Failed to decode base64 content")
            print("Raw content length:", len(content))
            return False
        
        # Check if it looks like a bcrypt hash
        if decoded.startswith(b'$2b$') or decoded.startswith(b'$2a$'):
            print("✓ Content appears to be a valid bcrypt hash")
            return True
        else:
            print("✗ Content does not appear to be a bcrypt hash")
            print("Decoded content starts with:", decoded[:10])
            return False
            
    except Exception as e:
        print(f"Error reading or processing file: {e}")
        return False

if name == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 check_password.py <path_to_password_file>")
        sys.exit(1)
    
    check_password_file(sys.argv[1])