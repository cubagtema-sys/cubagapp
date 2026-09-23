import os

PAYMENTS_FILE = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag-backend/routes/payments.py"

with open(PAYMENTS_FILE, "r", encoding="utf-8") as f:
    content = f.read()

# Replace _send_receipt_email with the newly redesigned, executive receipt template
old_email_func = '''def _send_receipt_email(to_email, member_name, amount, description, payment_id, custom_msg=""):
    resend.api_key = os.getenv('RESEND_API_KEY')
    if not resend.api_key:
        logger.error('[Resend] RESEND_API_KEY not configured — receipt email not sent.')
        return

    sender_email = os.getenv('SMTP_USER', 'eaap2026@eventslabs.org')

    html = f"""
    <div style="font-family:Arial,sans-serif;max-width:520px;margin:auto;padding:32px;border:1px solid #eee;border-radius:12px">
      <h2 style="color:#FF5000">CUBAG</h2>
      <p>Hi <strong>{member_name}</strong>,</p>
      <p>Your payment has been confirmed. Here is your receipt:</p>
      {custom_msg}
      <table style="width:100%;border-collapse:collapse">
        <tr><td style="padding:10px 0;border-bottom:1px solid #eee;color:#888">Description</td><td style="text-align:right;font-weight:700">{description}</td></tr>
        <tr><td style="padding:10px 0;border-bottom:1px solid #eee;color:#888">Amount</td><td style="text-align:right;font-weight:900;color:#FF5000;font-size:1.2em">GH₵ {float(amount):.2f}</td></tr>
        <tr><td style="padding:10px 0;border-bottom:1px solid #eee;color:#888">TX ID</td><td style="text-align:right">{payment_id}</td></tr>
        <tr><td style="padding:10px 0;color:#888">Status</td><td style="text-align:right"><span style="background:#d1fae5;color:#10b981;padding:2px 10px;border-radius:20px;font-size:0.8em;font-weight:800">PAID</span></td></tr>
      </table>
      <p style="margin-top:24px;color:#888;font-size:0.85em">Thank you for your payment. This is an automated receipt from CUBAG.</p>
    </div>
    """

    try:
        params = {
            "from": f"CUBAG Support <{sender_email}>",
            "to": [to_email],
            "subject": f'CUBAG Payment Receipt — GH₵ {float(amount):.2f}',
            "html": html,
        }
        resend.Emails.send(params)
        logger.info(f'[Resend] Receipt sent to {to_email} for payment {payment_id}')
    except Exception as e:
        logger.warning(f'[Resend] Failed to send receipt to {to_email}: {e}')'''

new_email_func = '''def _send_receipt_email(to_email, member_name, amount, description, payment_id=None, custom_msg=""):
    import datetime
    resend.api_key = os.getenv('RESEND_API_KEY')
    if not resend.api_key:
        logger.info('[Resend] RESEND_API_KEY not configured — mock receipt logged.')
        return

    sender_email = os.getenv('SMTP_USER', 'eaap2026@eventslabs.org')
    now_str = datetime.datetime.now().strftime("%B %d, %Y at %I:%M %p")
    formatted_amount = f"GH₵ {float(amount):,.2f}"

    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>CUBAG Official Payment Receipt</title>
    </head>
    <body style="margin:0;padding:0;background-color:#F1F5F9;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased;">
      <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#F1F5F9;padding:30px 15px;">
        <tr>
          <td align="center">
            <table width="100%" cellpadding="0" cellspacing="0" style="max-width:580px;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 20px rgba(0,0,0,0.06);border:1px solid #E2E8F0;">
              <!-- TOP EXECUTIVE HEADER -->
              <tr>
                <td style="background:linear-gradient(135deg, #1E110B 0%, #381E13 100%);padding:28px 32px;text-align:left;border-bottom:3px solid #FF5000;">
                  <table width="100%" cellpadding="0" cellspacing="0">
                    <tr>
                      <td>
                        <div style="display:inline-block;background:#FF5000;color:#ffffff;font-size:12px;font-weight:900;letter-spacing:1px;padding:4px 10px;border-radius:6px;margin-bottom:8px;">CUBAG</div>
                        <h1 style="margin:0;color:#ffffff;font-size:19px;font-weight:800;letter-spacing:0.3px;">CUSTOMS BROKERS ASSOCIATION OF GHANA</h1>
                        <p style="margin:4px 0 0 0;color:#E2E8F0;font-size:12px;opacity:0.85;">Official Payment Acknowledgement & Receipt</p>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>

              <!-- BODY CONTAINER -->
              <tr>
                <td style="padding:32px 32px 24px 32px;">
                  <div style="background:#ECFDF5;border:1px solid #A7F3D0;border-radius:10px;padding:12px 16px;margin-bottom:24px;">
                    <table width="100%" cellpadding="0" cellspacing="0">
                      <tr>
                        <td width="24" valign="middle" style="color:#059669;font-size:16px;font-weight:bold;">✓</td>
                        <td style="color:#065F46;font-size:13.5px;font-weight:700;padding-left:8px;">Payment Confirmed & Verified</td>
                      </tr>
                    </table>
                  </div>

                  <p style="margin:0 0 16px 0;color:#1E293B;font-size:15px;line-height:1.5;">
                    Dear <strong>{member_name}</strong>,
                  </p>
                  <p style="margin:0 0 20px 0;color:#475569;font-size:13.5px;line-height:1.6;">
                    Thank you for your payment to the Customs Brokers Association of Ghana. This email serves as your official electronic receipt and acknowledgement of confirmed funds.
                  </p>

                  {f'<div style="background:#FFF7ED;border-left:4px solid #FF5000;padding:14px 16px;border-radius:0 8px 8px 0;margin-bottom:22px;color:#9A3412;font-size:13px;line-height:1.5;">{custom_msg}</div>' if custom_msg else ''}

                  <!-- RECEIPT INVOICE TABLE -->
                  <table width="100%" cellpadding="0" cellspacing="0" style="border:1px solid #E2E8F0;border-radius:12px;overflow:hidden;margin-bottom:24px;">
                    <tr style="background:#F8FAFC;border-bottom:1px solid #E2E8F0;">
                      <th colspan="2" style="padding:12px 16px;text-align:left;color:#475569;font-size:11px;font-weight:800;letter-spacing:0.5px;text-transform:uppercase;">
                        Receipt Breakdown
                      </th>
                    </tr>
                    <tr>
                      <td style="padding:14px 16px;border-bottom:1px solid #F1F5F9;color:#64748B;font-size:13px;">Service / Purpose</td>
                      <td style="padding:14px 16px;border-bottom:1px solid #F1F5F9;color:#0F172A;font-size:13.5px;font-weight:700;text-align:right;">{description}</td>
                    </tr>
                    <tr>
                      <td style="padding:14px 16px;border-bottom:1px solid #F1F5F9;color:#64748B;font-size:13px;">Payment Date</td>
                      <td style="padding:14px 16px;border-bottom:1px solid #F1F5F9;color:#334155;font-size:13px;text-align:right;">{now_str}</td>
                    </tr>
                    <tr>
                      <td style="padding:14px 16px;border-bottom:1px solid #F1F5F9;color:#64748B;font-size:13px;">Payment Status</td>
                      <td style="padding:14px 16px;border-bottom:1px solid #F1F5F9;text-align:right;">
                        <span style="background:#D1FAE5;color:#065F46;padding:4px 10px;border-radius:20px;font-size:11px;font-weight:800;letter-spacing:0.3px;">PAID & CLEARED</span>
                      </td>
                    </tr>
                    <tr style="background:#FFFBF8;">
                      <td style="padding:16px 16px;color:#1E293B;font-size:14px;font-weight:800;">Total Amount Paid</td>
                      <td style="padding:16px 16px;color:#FF5000;font-size:18px;font-weight:900;text-align:right;">{formatted_amount}</td>
                    </tr>
                  </table>

                  <p style="margin:0 0 8px 0;color:#64748B;font-size:12px;line-height:1.5;">
                    If you have questions regarding this transaction, please contact the CUBAG Secretariat directly via your Member Portal.
                  </p>
                </td>
              </tr>

              <!-- FOOTER -->
              <tr>
                <td style="background:#F8FAFC;padding:20px 32px;border-top:1px solid #E2E8F0;text-align:center;">
                  <p style="margin:0 0 4px 0;color:#1E293B;font-size:12px;font-weight:700;">Customs Brokers Association of Ghana (CUBAG)</p>
                  <p style="margin:0;color:#94A3B8;font-size:11px;">National Secretariat • Tema Port & KIA Chapters • Ghana</p>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """

    try:
        params = {
            "from": f"CUBAG Secretariat <{sender_email}>",
            "to": [to_email],
            "subject": f'Official Payment Receipt: {description} ({formatted_amount})',
            "html": html,
        }
        resend.Emails.send(params)
        logger.info(f'[Resend] Official executive receipt sent to {to_email} for {description}')
    except Exception as e:
        logger.warning(f'[Resend] Failed to send receipt to {to_email}: {e}')'''

if old_email_func in content:
    content = content.replace(old_email_func, new_email_func)
    with open(PAYMENTS_FILE, "w", encoding="utf-8") as f:
        f.write(content)
    print("Updated _send_receipt_email in payments.py successfully")
else:
    print("Could not find exact old _send_receipt_email string")
