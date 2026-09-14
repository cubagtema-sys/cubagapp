import os

PAYMENTS_FILE = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/lib/pages/payments_page.dart"
DOCS_FILE = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/lib/pages/application_documents_page.dart"

# 1. Update application_documents_page.dart - remove PAY IN FULL badge
with open(DOCS_FILE, "r", encoding="utf-8") as f:
    docs_content = f.read()

old_docs_badge = """                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _kGreen.withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'PAY IN FULL',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: _kGreen,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),"""

if old_docs_badge in docs_content:
    docs_content = docs_content.replace(old_docs_badge, "")
    with open(DOCS_FILE, "w", encoding="utf-8") as f:
        f.write(docs_content)
    print("Removed PAY IN FULL from application_documents_page.dart")
else:
    print("Could not find old_docs_badge")

# 2. Update payments_page.dart
with open(PAYMENTS_FILE, "r", encoding="utf-8") as f:
    pay_content = f.read()

# Add _isRegFeePaid state variable
if "bool _isRegFeePaid = false;" not in pay_content:
    pay_content = pay_content.replace("bool _isLicenseBlocked = false;", "bool _isLicenseBlocked = false;\n  bool _isRegFeePaid = false;")

# In _loadData:
old_loaddata_reg = """      String? dynamicRegAmt;
      if (docRes is Response && docRes.data is Map) {
        final docData = docRes.data as Map;
        dynamicRegAmt = docData['registration_fee_amount']?.toString();
        if (dynamicRegAmt != null && double.tryParse(dynamicRegAmt) != null) {
          _regFeeAmountStr = double.parse(dynamicRegAmt).toStringAsFixed(2);
        }
        _regFeeCategoryTitle = docData['fee_category_title']?.toString() ?? '';
        final rawBreakdown = docData['registration_fee_breakdown'];
        if (rawBreakdown is List) {
          _regFeeBreakdown = rawBreakdown
              .map((x) => Map<String, dynamic>.from(x as Map))
              .toList();
        }
      }"""

new_loaddata_reg = """      String? dynamicRegAmt;
      bool regPaidFromDoc = false;
      if (docRes is Response && docRes.data is Map) {
        final docData = docRes.data as Map;
        dynamicRegAmt = docData['registration_fee_amount']?.toString();
        if (dynamicRegAmt != null && double.tryParse(dynamicRegAmt) != null) {
          _regFeeAmountStr = double.parse(dynamicRegAmt).toStringAsFixed(2);
        }
        _regFeeCategoryTitle = docData['fee_category_title']?.toString() ?? '';
        regPaidFromDoc = docData['registration_fee_paid'] == true || docData['application_fee_paid'] == true;
        final rawBreakdown = docData['registration_fee_breakdown'];
        if (rawBreakdown is List) {
          _regFeeBreakdown = rawBreakdown
              .map((x) => Map<String, dynamic>.from(x as Map))
              .toList();
        }
      }"""

if old_loaddata_reg in pay_content:
    pay_content = pay_content.replace(old_loaddata_reg, new_loaddata_reg)

# Update setState in _loadData:
old_setstate_block = """          // Extract member info from /auth/me response
          if (meRes is Response && meRes.data is Map) {
            _memberInfo =
                (meRes.data['member'] ?? meRes.data) as Map<String, dynamic>;
            final rawRenewalBreakdown = _memberInfo['renewal_fee_breakdown'];
            if (rawRenewalBreakdown is List) {
              _renewalFeeBreakdown = rawRenewalBreakdown
                  .map((x) => Map<String, dynamic>.from(x as Map))
                  .toList();
            }
            _renewalFeeCategoryTitle =
                _memberInfo['renewal_fee_title']?.toString() ?? '';
            final rawRenewalAmt = _memberInfo['renewal_fee_amount'];
            if (rawRenewalAmt != null) {
              _renewalFeeAmount = double.tryParse(rawRenewalAmt.toString());
            }
          }"""

new_setstate_block = """          // Extract member info from /auth/me response
          if (meRes is Response && meRes.data is Map) {
            _memberInfo =
                (meRes.data['member'] ?? meRes.data) as Map<String, dynamic>;
            final rawRenewalBreakdown = _memberInfo['renewal_fee_breakdown'];
            if (rawRenewalBreakdown is List) {
              _renewalFeeBreakdown = rawRenewalBreakdown
                  .map((x) => Map<String, dynamic>.from(x as Map))
                  .toList();
            }
            _renewalFeeCategoryTitle =
                _memberInfo['renewal_fee_title']?.toString() ?? '';
            final rawRenewalAmt = _memberInfo['renewal_fee_amount'];
            if (rawRenewalAmt != null) {
              _renewalFeeAmount = double.tryParse(rawRenewalAmt.toString());
            }
            _isRegFeePaid = regPaidFromDoc ||
                _memberInfo['registration_fee_paid'] == true ||
                _memberInfo['registration_paid'] == true ||
                _memberInfo['status']?.toString().toLowerCase() == 'active';
          } else {
            _isRegFeePaid = regPaidFromDoc;
          }"""

if old_setstate_block in pay_content:
    pay_content = pay_content.replace(old_setstate_block, new_setstate_block)

# Check query parameter and initial _reason:
old_reason_init = """          if (queryFee != null && queryFee.isNotEmpty) {
            _reason = queryFee;
          } else if (redirectUrl == '/application-documents' ||
              _reason.isEmpty) {
            _reason = 'Registration Fee';
          }"""

new_reason_init = """          if (queryFee != null && queryFee.isNotEmpty) {
            _reason = queryFee;
          } else if (redirectUrl == '/application-documents') {
            _reason = _isRegFeePaid ? 'Annual Renewal Dues' : (_regFeeCategoryTitle.isNotEmpty ? _regFeeCategoryTitle : 'Registration Fee');
          } else if (_reason.isEmpty || (_isRegFeePaid && _reason.toLowerCase().contains('registration'))) {
            _reason = 'Annual Renewal Dues';
          }"""

if old_reason_init in pay_content:
    pay_content = pay_content.replace(old_reason_init, new_reason_init)

# Remove PAY IN FULL badges in payments_page.dart:
old_pay_badge1 = """                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10b981).withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'PAY IN FULL',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF059669),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),"""

pay_content = pay_content.replace(old_pay_badge1, "")

# Dropdown list logic:
old_dropdown_builder = """              final regTitle = _regFeeCategoryTitle.isNotEmpty
                  ? 'Registration Fee ($_regFeeCategoryTitle)'
                  : 'Registration Fee';
              final regAmtStr = _regFeeAmountStr;

              final renewalTitle = _renewalFeeCategoryTitle.isNotEmpty
                  ? 'Annual Renewal Dues ($_renewalFeeCategoryTitle)'
                  : 'Annual Renewal Dues';
              final renewalAmtStr =
                  _renewalFeeAmount != null && _renewalFeeAmount! > 0
                  ? _renewalFeeAmount!.toStringAsFixed(2)
                  : '2170.00';

              final List<DropdownItem<String>> dropdownItems = [
                DropdownItem<String>(
                  value: 'Registration Fee',
                  label: '$regTitle · GH₵ $regAmtStr',
                ),
                DropdownItem<String>(
                  value: 'Annual Renewal Dues',
                  label: '$renewalTitle · GH₵ $renewalAmtStr',
                ),
              ];"""

new_dropdown_builder = """              final regTitle = _regFeeCategoryTitle.isNotEmpty
                  ? _regFeeCategoryTitle
                  : 'Registration Fee';
              final regAmtStr = _regFeeAmountStr;

              final renewalTitle = _renewalFeeCategoryTitle.isNotEmpty
                  ? 'Annual Renewal Dues ($_renewalFeeCategoryTitle)'
                  : 'Annual Renewal Dues';
              final renewalAmtStr =
                  _renewalFeeAmount != null && _renewalFeeAmount! > 0
                  ? _renewalFeeAmount!.toStringAsFixed(2)
                  : '2170.00';

              final List<DropdownItem<String>> dropdownItems = [];
              if (!_isRegFeePaid) {
                dropdownItems.add(
                  DropdownItem<String>(
                    value: regTitle,
                    label: '$regTitle · GH₵ $regAmtStr',
                  ),
                );
              }
              dropdownItems.add(
                DropdownItem<String>(
                  value: 'Annual Renewal Dues',
                  label: '$renewalTitle · GH₵ $renewalAmtStr',
                ),
              );"""

if old_dropdown_builder in pay_content:
    pay_content = pay_content.replace(old_dropdown_builder, new_dropdown_builder)

# Also ensure auto-select fallback doesn't re-insert Registration Fee if already paid:
old_autoselect_fix = """                if (_reason.toLowerCase().contains('registration')) {
                  labelText = '$regTitle · GH₵ $regAmtStr';
                } else if (_reason.toLowerCase().contains('renewal')) {
                  labelText = '$renewalTitle · GH₵ $renewalAmtStr';
                }
                dropdownItems.insert(
                  0,
                  DropdownItem<String>(value: _reason, label: labelText),
                );"""

new_autoselect_fix = """                if (_reason.toLowerCase().contains('registration')) {
                  if (_isRegFeePaid) {
                    _reason = 'Annual Renewal Dues';
                  } else {
                    labelText = '$regTitle · GH₵ $regAmtStr';
                    dropdownItems.insert(
                      0,
                      DropdownItem<String>(value: _reason, label: labelText),
                    );
                  }
                } else if (_reason.toLowerCase().contains('renewal')) {
                  labelText = '$renewalTitle · GH₵ $renewalAmtStr';
                  dropdownItems.insert(
                    0,
                    DropdownItem<String>(value: _reason, label: labelText),
                  );
                } else {
                  dropdownItems.insert(
                    0,
                    DropdownItem<String>(value: _reason, label: labelText),
                  );
                }"""

if old_autoselect_fix in pay_content:
    pay_content = pay_content.replace(old_autoselect_fix, new_autoselect_fix)

with open(PAYMENTS_FILE, "w", encoding="utf-8") as f:
    f.write(pay_content)

print("Updated payments_page.dart successfully")
