#!/usr/bin/env python3
"""
Complete Security Validation - Validates all security improvements across all phases.
"""
import sys
import os

def run_phase1_validation():
    """Run Phase 1 security validation."""
    print("Running Phase 1 Security Validation...")
    result = os.system("python3 validate_phase1_security.py")
    return result == 0

def run_phase2_validation():
    """Run Phase 2 payment security validation."""
    print("\nRunning Phase 2 Payment Security Validation...")
    result = os.system("python3 validate_phase2_payment.py")
    return result == 0

def run_phase3_validation():
    """Run Phase 3 privacy validation."""
    print("\nRunning Phase 3 Privacy Validation...")
    result = os.system("python3 validate_phase3_privacy.py")
    return result == 0

def main():
    """Run all phase validations."""
    print("=" * 60)
    print("COMPLETE SECURITY VALIDATION - ALL PHASES")
    print("=" * 60)
    
    results = {
        'Phase 1 (Security)': run_phase1_validation(),
        'Phase 2 (Payment Security)': run_phase2_validation(),
        'Phase 3 (Privacy)': run_phase3_validation(),
    }
    
    print("\n" + "=" * 60)
    print("VALIDATION SUMMARY")
    print("=" * 60)
    
    for phase, passed in results.items():
        status = "✓ PASSED" if passed else "✗ FAILED"
        print(f"{phase}: {status}")
    
    all_passed = all(results.values())
    
    print("\n" + "=" * 60)
    if all_passed:
        print("✓ ALL SECURITY PHASES VALIDATED SUCCESSFULLY")
        print("=" * 60)
        return 0
    else:
        print("✗ SOME SECURITY PHASES FAILED VALIDATION")
        print("=" * 60)
        return 1

if __name__ == '__main__':
    sys.exit(main())