"""
PII Encryption at Rest - Encrypts sensitive personal information for storage.
"""
import logging
import os
import base64
from typing import Optional, Dict, Any
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

logger = logging.getLogger(__name__)


class PIIEncryptionManager:
    """
    Manages encryption and decryption of PII (Personally Identifiable Information).
    """
    
    # Fields that should be encrypted at rest
    ENCRYPTED_FIELDS = {
        'phone',
        'digital_address',
        'tin',
        'account_number',  # For payment records
        'account_name',     # For payment records
    }
    
    def __init__(self, encryption_key: Optional[str] = None):
        """
        Initialize the encryption manager.
        
        Args:
            encryption_key: Encryption key (if None, uses environment variable)
        """
        self.encryption_key = encryption_key or os.getenv('PII_ENCRYPTION_KEY')
        
        if not self.encryption_key:
            logger.warning("PII_ENCRYPTION_KEY not set - PII encryption disabled")
            self.fernet = None
        else:
            try:
                # Ensure the key is in the correct format for Fernet
                if len(self.encryption_key) != 44:  # Fernet key must be 44 bytes (base64)
                    # Derive a proper key from the provided key
                    kdf = PBKDF2HMAC(
                        algorithm=hashes.SHA256(),
                        length=32,
                        salt=b'cubag_pii_salt',  # In production, use a random salt per deployment
                        iterations=100000,
                    )
                    key = kdf.derive(self.encryption_key.encode())
                    self.encryption_key = base64.urlsafe_b64encode(key).decode()
                
                self.fernet = Fernet(self.encryption_key.encode())
                logger.info("PII encryption manager initialized")
            except Exception as e:
                logger.error(f"Failed to initialize PII encryption: {e}")
                self.fernet = None
    
    def encrypt(self, plaintext: str) -> Optional[str]:
        """
        Encrypt plaintext data.
        
        Args:
            plaintext: Plain text to encrypt
            
        Returns:
            Encrypted string or None if encryption fails
        """
        if not self.fernet or not plaintext:
            return plaintext
        
        try:
            encrypted = self.fernet.encrypt(plaintext.encode())
            return base64.urlsafe_b64encode(encrypted).decode()
        except Exception as e:
            logger.error(f"Encryption failed: {e}")
            return plaintext
    
    def decrypt(self, ciphertext: str) -> Optional[str]:
        """
        Decrypt encrypted data.
        
        Args:
            ciphertext: Encrypted string
            
        Returns:
            Decrypted plaintext or None if decryption fails
        """
        if not self.fernet or not ciphertext:
            return ciphertext
        
        try:
            encrypted_bytes = base64.urlsafe_b64decode(ciphertext.encode())
            decrypted = self.fernet.decrypt(encrypted_bytes)
            return decrypted.decode()
        except Exception as e:
            logger.error(f"Decryption failed: {e}")
            return ciphertext
    
    def encrypt_dict(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Encrypt sensitive fields in a dictionary.
        
        Args:
            data: Dictionary containing potentially sensitive data
            
        Returns:
            Dictionary with encrypted sensitive fields
        """
        encrypted_data = data.copy()
        
        for field in self.ENCRYPTED_FIELDS:
            if field in encrypted_data and encrypted_data[field]:
                encrypted_data[field] = self.encrypt(str(encrypted_data[field]))
        
        return encrypted_data
    
    def decrypt_dict(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Decrypt sensitive fields in a dictionary.
        
        Args:
            data: Dictionary containing potentially encrypted data
            
        Returns:
            Dictionary with decrypted sensitive fields
        """
        decrypted_data = data.copy()
        
        for field in self.ENCRYPTED_FIELDS:
            if field in decrypted_data and decrypted_data[field]:
                decrypted_data[field] = self.decrypt(str(decrypted_data[field]))
        
        return decrypted_data
    
    def is_encryption_enabled(self) -> bool:
        """Check if encryption is properly enabled."""
        return self.fernet is not None


# Global encryption manager instance
_encryption_manager = None


def get_encryption_manager() -> PIIEncryptionManager:
    """Get the global encryption manager instance."""
    global _encryption_manager
    if _encryption_manager is None:
        _encryption_manager = PIIEncryptionManager()
    return _encryption_manager


def encrypt_field(field_name: str, value: Any) -> Any:
    """
    Convenience function to encrypt a field if it's in the encrypted fields list.
    
    Args:
        field_name: Name of the field
        value: Value to encrypt
        
    Returns:
        Encrypted value if field is sensitive, original value otherwise
    """
    manager = get_encryption_manager()
    if field_name in manager.ENCRYPTED_FIELDS and value:
        return manager.encrypt(str(value))
    return value


def decrypt_field(field_name: str, value: Any) -> Any:
    """
    Convenience function to decrypt a field if it's in the encrypted fields list.
    
    Args:
        field_name: Name of the field
        value: Value to decrypt
        
    Returns:
        Decrypted value if field is sensitive, original value otherwise
    """
    manager = get_encryption_manager()
    if field_name in manager.ENCRYPTED_FIELDS and value:
        return manager.decrypt(str(value))
    return value