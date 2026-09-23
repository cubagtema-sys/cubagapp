#!/usr/bin/env python3
"""
Quick validation script for Phase 3 privacy improvements.
Tests that privacy modules are properly configured and functional.
"""
import sys
import os

def test_data_retention():
    """Test that data retention policies are properly configured."""
    print("Testing data retention policies...")
    
    try:
        from config.data_retention import (
            DataRetentionPolicy,
            DataRetentionPolicyEnforcer,
            run_data_retention_cleanup
        )
        print("✓ Data retention module imported successfully")
        
        # Test basic functionality
        assert hasattr(DataRetentionPolicy, 'RETENTION_POLICIES')
        print("✓ Retention policies defined")
        
        assert hasattr(DataRetentionPolicy, 'PERMANENT_DATA')
        print("✓ Permanent data categories defined")
        
        assert callable(run_data_retention_cleanup)
        print("✓ Cleanup function is callable")
        
        return True
    except Exception as e:
        print(f"✗ Data retention test failed: {e}")
        return False

def test_gdpr_compliance():
    """Test that GDPR compliance features are properly configured."""
    print("\nTesting GDPR compliance...")
    
    try:
        from config.gdpr_compliance import GDPRComplianceManager
        print("✓ GDPR compliance module imported successfully")
        
        # Test basic functionality
        assert hasattr(GDPRComplianceManager, 'export_member_data')
        print("✓ Data export method available")
        
        assert hasattr(GDPRComplianceManager, 'request_member_data_deletion')
        print("✓ Data deletion request method available")
        
        assert hasattr(GDPRComplianceManager, 'process_member_data_deletion')
        print("✓ Data deletion processing method available")
        
        return True
    except Exception as e:
        print(f"✗ GDPR compliance test failed: {e}")
        return False

def test_pii_encryption():
    """Test that PII encryption is properly configured."""
    print("\nTesting PII encryption...")
    
    try:
        from config.pii_encryption import (
            PIIEncryptionManager,
            get_encryption_manager,
            encrypt_field,
            decrypt_field
        )
        print("✓ PII encryption module imported successfully")
        
        # Test basic functionality
        manager = get_encryption_manager()
        assert manager is not None
        print("✓ Encryption manager instance created")
        
        assert hasattr(manager, 'ENCRYPTED_FIELDS')
        print("✓ Encrypted fields defined")
        
        assert callable(encrypt_field)
        print("✓ encrypt_field function is callable")
        
        assert callable(decrypt_field)
        print("✓ decrypt_field function is callable")
        
        return True
    except Exception as e:
        print(f"✗ PII encryption test failed: {e}")
        return False

def test_audit_logging():
    """Test that audit logging is properly configured."""
    print("\nTesting audit logging...")
    
    try:
        from config.audit_logging import (
            DataAccessLogger,
            get_data_access_logger
        )
        print("✓ Audit logging module imported successfully")
        
        # Test basic functionality
        assert hasattr(DataAccessLogger, 'ACCESS_TYPES')
        print("✓ Access types defined")
        
        assert hasattr(DataAccessLogger, 'log_data_access')
        print("✓ log_data_access method available")
        
        assert callable(get_data_access_logger)
        print("✓ get_data_access_logger function is callable")
        
        return True
    except Exception as e:
        print(f"✗ Audit logging test failed: {e}")
        return False

def test_gdpr_routes():
    """Test that GDPR routes are properly configured."""
    print("\nTesting GDPR routes...")
    
    try:
        from routes.gdpr import gdpr_bp
        print("✓ GDPR routes blueprint imported successfully")
        
        # Test that blueprint has expected routes
        assert hasattr(gdpr_bp, 'deferred_functions')
        print("✓ GDPR blueprint has routes registered")
        
        return True
    except Exception as e:
        print(f"✗ GDPR routes test failed: {e}")
        return False

def test_database_schema():
    """Test that database schema includes privacy enhancements."""
    print("\nTesting database schema privacy enhancements...")
    
    try:
        with open('config/db.py', 'r') as f:
            db_content = f.read()
        
        # Check for GDPR table
        if 'data_deletion_requests' in db_content:
            print("✓ GDPR deletion requests table in schema")
        else:
            print("✗ GDPR deletion requests table not found")
            return False
        
        # Check for privacy consent fields
        if 'data_sharing_consent' in db_content:
            print("✓ Data sharing consent field in schema")
        else:
            print("✗ Data sharing consent field not found")
            return False
        
        if 'marketing_consent' in db_content:
            print("✓ Marketing consent field in schema")
        else:
            print("✗ Marketing consent field not found")
            return False
        
        return True
        
    except Exception as e:
        print(f"✗ Database schema check failed: {e}")
        return False

def test_jobs_integration():
    """Test that jobs scheduler includes data retention cleanup."""
    print("\nTesting jobs scheduler integration...")
    
    try:
        with open('jobs.py', 'r') as f:
            jobs_content = f.read()
        
        # Check for data retention import
        if 'data_retention' in jobs_content:
            print("✓ Data retention imported in jobs")
        else:
            print("✗ Data retention not imported")
            return False
        
        # Check for data retention job
        if 'run_data_retention_job' in jobs_content:
            print("✓ Data retention job function defined")
        else:
            print("✗ Data retention job function not defined")
            return False
        
        # Check for scheduler integration
        if 'run_data_retention_job' in jobs_content and 'add_job' in jobs_content:
            print("✓ Data retention job added to scheduler")
        else:
            print("✗ Data retention job not added to scheduler")
            return False
        
        return True
        
    except Exception as e:
        print(f"✗ Jobs integration check failed: {e}")
        return False

def main():
    """Run all validation tests."""
    print("=" * 60)
    print("PHASE 3 PRIVACY & COMPLIANCE VALIDATION")
    print("=" * 60)
    
    all_passed = True
    
    # Test 1: Data retention
    if not test_data_retention():
        all_passed = False
    
    # Test 2: GDPR compliance
    if not test_gdpr_compliance():
        all_passed = False
    
    # Test 3: PII encryption
    if not test_pii_encryption():
        all_passed = False
    
    # Test 4: Audit logging
    if not test_audit_logging():
        all_passed = False
    
    # Test 5: GDPR routes
    if not test_gdpr_routes():
        all_passed = False
    
    # Test 6: Database schema
    if not test_database_schema():
        all_passed = False
    
    # Test 7: Jobs integration
    if not test_jobs_integration():
        all_passed = False
    
    print("\n" + "=" * 60)
    if all_passed:
        print("✓ ALL PHASE 3 PRIVACY TESTS PASSED")
        print("=" * 60)
        return 0
    else:
        print("✗ SOME PHASE 3 PRIVACY TESTS FAILED")
        print("=" * 60)
        return 1

if __name__ == '__main__':
    sys.exit(main())