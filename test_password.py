import bcrypt
import base64
import sys

def encrypt_password(password):
    """Encrypt a password using bcrypt and return base64 encoded string"""
    password = password.encode('utf-8')
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password, salt)
    return base64.b64encode(hashed).decode('utf-8')

def verify_password(password, hashed_b64):
    """Verify a password against a base64 encoded bcrypt hash"""
    try:
        password = password.encode('utf-8')
        hashed = base64.b64decode(hashed_b64)
        return bcrypt.checkpw(password, hashed)
    except Exception as e:
        print(f"Error during verification: {e}")
        return False

def main():
    # Test with a sample password
    test_password = "YourTestPassword123!"
    
    # Encrypt it
    encrypted = encrypt_password(test_password)
    print(f"\nEncrypted hash (base64): {encrypted}")
    
    # Verify it
    if verify_password(test_password, encrypted):
        print("✓ Password verification successful")
    else:
        print("✗ Password verification failed")
    
    # If a password file is provided, test against it
    if len(sys.argv) > 1:
        with open(sys.argv[1], 'r') as f:
            stored_hash = f.read().strip()
        
        test_input = input("\nEnter the password to test against the stored hash: ")
        if verify_password(test_input, stored_hash):
            print("✓ Password matches stored hash")
        else:
            print("✗ Password does not match stored hash")

if __name__ == "__main__":
    main() 