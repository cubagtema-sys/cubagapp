"""The one branded look for every email CUBAG sends.

Email clients ignore <style> blocks and web fonts, so everything is inline
CSS in a simple table layout that renders in Gmail, Outlook and phone mail
apps. ``branded()`` wraps whatever a sender built (HTML fragment or plain
text) in the CUBAG header, card and footer; it is safe to call twice.
"""
import html as _html
import os
import re

MARKER = '<!--cubag-email-->'

# Brand tokens (same as the app: lib/design/cubag_design.dart).
COCOA = '#5C3421'
ACTION = '#C2410C'
INK = '#2A1810'
INK_SOFT = '#4A3A32'
MUTED = '#6E625B'
SAND = '#F7F4F1'
LINE = '#E9E2DB'

PHONE = '030 321 6577'
EMAIL = 'info@cubag.org'
FONT = "-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"


def _base_url():
    return (os.getenv('PUBLIC_BASE_URL') or 'https://cubag-api-server.fly.dev').rstrip('/')


def logo_url():
    """Small logo served with the web app (cubag_flutter/web/email/)."""
    return f"{_base_url()}/email/cubag-logo.jpg"


def button(label, url):
    """A bulletproof call-to-action button (works in Outlook too)."""
    return (
        f'<table role="presentation" cellpadding="0" cellspacing="0" style="margin:24px 0 8px;">'
        f'<tr><td style="background:{ACTION};border-radius:10px;">'
        f'<a href="{_html.escape(url, quote=True)}" style="display:inline-block;padding:13px 22px;'
        f'font-family:{FONT};font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;">'
        f'{_html.escape(label)}</a></td></tr></table>'
    )


def code_box(code):
    """Large, easy-to-read one-time code."""
    return (
        f'<div style="margin:24px 0;padding:18px 0;text-align:center;background:{SAND};'
        f'border:1px solid {LINE};border-radius:12px;font-family:{FONT};font-size:34px;'
        f'font-weight:800;letter-spacing:10px;color:{INK};">{_html.escape(str(code))}</div>'
    )


def paragraph(text, muted=False, small=False):
    color = MUTED if muted else INK_SOFT
    size = 13 if small else 16
    return (f'<p style="margin:0 0 14px;font-family:{FONT};font-size:{size}px;line-height:1.6;color:{color};">'
            f'{text}</p>')


def text_to_html(text):
    """Plain text email body -> paragraphs (keeps line breaks, escapes HTML)."""
    blocks = [b.strip('\n') for b in re.split(r'\n\s*\n', (text or '').strip()) if b.strip()]
    out = []
    for b in blocks:
        lines = b.split('\n')
        # A short line on its own made only of digits/letters is a code: make it big.
        if len(lines) == 1 and re.fullmatch(r'\s*[A-Z0-9]{4,10}\s*', lines[0]):
            out.append(code_box(lines[0].strip()))
            continue
        out.append(paragraph('<br>'.join(_html.escape(l.strip()) for l in lines)))
    return ''.join(out)


def _restyle_fragment(fragment):
    """Old senders built their own boxes in other colours; keep their content,
    drop their outer frame and swap their accent colours for the brand ones."""
    f = fragment
    f = re.sub(r'#FF5000|#ff5000|#ea580c|#EA580C|#f97316|#F97316', ACTION, f)
    f = re.sub(r'#0f172a|#1e293b|#111827', INK, f)
    f = re.sub(r'#475569|#334155|#64748b', INK_SOFT, f)
    f = re.sub(r'#94a3b8|#9ca3af', MUTED, f)
    f = re.sub(r'#f8fafc|#f1f5f9', SAND, f)
    f = re.sub(r'#e2e8f0|#cbd5e1', LINE, f)
    f = re.sub(r'font-family:\s*Arial,\s*sans-serif;?', f'font-family:{FONT};', f)
    # Bare tags from simple senders get the brand text style.
    body = f'font-family:{FONT};font-size:16px;line-height:1.6;color:{INK_SOFT};'
    f = re.sub(r'<p>', f'<p style="margin:0 0 14px;{body}">', f)
    f = re.sub(r'<(ul|ol)>', lambda m: f'<{m.group(1)} style="margin:0 0 14px;padding-left:20px;{body}">', f)
    f = re.sub(r'<li>', f'<li style="margin:0 0 6px;{body}">', f)
    f = re.sub(r'<h([1-3])>', lambda m: f'<h{m.group(1)} style="margin:0 0 12px;font-family:{FONT};font-size:20px;color:{INK};">', f)
    return f


def branded(body_html=None, body_text='', subject='', preheader=''):
    """Full branded email. ``body_html`` may be a fragment; when missing, the
    plain-text body is turned into paragraphs. Already-branded HTML is
    returned unchanged."""
    if body_html and MARKER in body_html:
        return body_html
    inner = _restyle_fragment(body_html) if body_html else text_to_html(body_text)
    title = _html.escape(subject or 'CUBAG')
    pre = _html.escape(preheader or '')
    return f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light only"><title>{title}</title></head>
<body style="margin:0;padding:0;background:{SAND};">{MARKER}
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">{pre}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:{SAND};">
<tr><td align="center" style="padding:28px 12px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;">
    <tr><td style="background:{COCOA};border-radius:16px 16px 0 0;padding:20px 28px;">
      <table role="presentation" cellpadding="0" cellspacing="0"><tr>
        <td style="vertical-align:middle;padding-right:14px;">
          <img src="{logo_url()}" width="48" height="48" alt="CUBAG"
               style="display:block;border-radius:24px;background:#ffffff;border:0;">
        </td>
        <td style="vertical-align:middle;font-family:{FONT};">
          <div style="font-size:18px;font-weight:800;color:#ffffff;letter-spacing:0.3px;">CUBAG</div>
          <div style="font-size:12px;color:#E8C4AE;">Customs Brokers Association of Ghana</div>
        </td>
      </tr></table>
    </td></tr>
    <tr><td style="background:#ffffff;border-left:1px solid {LINE};border-right:1px solid {LINE};padding:30px 28px 18px;">
      {inner}
    </td></tr>
    <tr><td style="background:#ffffff;border:1px solid {LINE};border-top:0;border-radius:0 0 16px 16px;padding:0 28px 26px;">
      <div style="border-top:1px solid {LINE};padding-top:16px;font-family:{FONT};font-size:13px;line-height:1.6;color:{MUTED};">
        CUBAG Secretariat<br>
        Phone <a href="tel:+233303216577" style="color:{MUTED};">{PHONE}</a> &middot;
        <a href="mailto:{EMAIL}" style="color:{MUTED};">{EMAIL}</a>
      </div>
    </td></tr>
    <tr><td style="padding:16px 8px;text-align:center;font-family:{FONT};font-size:12px;line-height:1.5;color:{MUTED};">
      Sent by the CUBAG Secretariat. If you have a question, call or email us.
    </td></tr>
  </table>
</td></tr></table>
</body></html>"""
