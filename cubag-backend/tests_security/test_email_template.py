"""Every email gets the CUBAG design; nothing is sent raw."""
from datetime import date

from config.email_template import MARKER, branded, code_box, text_to_html


def test_plain_text_gets_header_logo_footer():
    html = branded(None, 'Hello Kwame,\n\nYour licence ends soon.', 'Licence reminder')
    assert MARKER in html and 'email/cubag-logo.jpg' in html
    assert 'Customs Brokers Association of Ghana' in html
    assert '030 321 6577' in html and 'info@cubag.org' in html
    assert 'Your licence ends soon.' in html


def test_branding_twice_does_not_nest():
    once = branded('<p>Hi</p>', '', 'X')
    assert branded(once, '', 'X') == once


def test_bare_paragraphs_get_the_brand_font_and_old_colours_are_replaced():
    html = branded('<p>Approved.</p><div style="color:#FF5000;font-family:Arial,sans-serif">x</div>', '', 'X')
    assert '<p>' not in html and '#FF5000' not in html and 'Arial,sans-serif' not in html.replace('Helvetica,Arial,sans-serif', '')


def test_text_is_escaped_and_codes_are_big():
    assert '&lt;script&gt;' in text_to_html('<script>x</script>')
    assert 'letter-spacing' in text_to_html('Your code:\n\n482913')
    assert '482913' in code_box('482913')


def test_reminder_uses_the_template_pieces():
    from jobs import renewal_reminder_message
    _, _, html = renewal_reminder_message('Kwame Owusu', 7, date(2026, 12, 5))
    assert 'font-family' in html and 'Pay dues' in html
