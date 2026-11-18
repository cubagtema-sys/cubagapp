<?php
/**
 * Plugin Name: CUBAG Portal Connector
 * Plugin URI: https://cubag-api-server.fly.dev
 * Description: Official WordPress connector for Customs Brokers Association Ghana (CUBAG). Syncs and displays members in good standing, events, news, port operational bulletins, CTI courses, and member verification via shortcodes.
 * Version: 1.0.0
 * Author: CUBAG Technology Secretariat
 * Author URI: https://cubag-api-server.fly.dev
 * License: GPL-2.0+
 */

if (!defined('ABSPATH')) {
    exit;
}

class CUBAG_Portal_Connector {
    private const API_BASE = 'https://cubag-api-server.fly.dev/api/v1/public';
    private const CACHE_TTL = 300; // 5 minutes cache in WordPress transients

    public function __construct() {
        // Register Shortcodes
        add_shortcode('cubag_members', [$this, 'render_members']);
        add_shortcode('cubag_verify_member', [$this, 'render_verify_member']);
        add_shortcode('cubag_events', [$this, 'render_events']);
        add_shortcode('cubag_news', [$this, 'render_news']);
        add_shortcode('cubag_bulletins', [$this, 'render_bulletins']);
        add_shortcode('cubag_courses', [$this, 'render_courses']);
        add_shortcode('cubag_rates', [$this, 'render_exchange_rates']);
        add_shortcode('cubag_portal_summary', [$this, 'render_portal_summary']);

        // Register frontend styles
        add_action('wp_enqueue_scripts', [$this, 'enqueue_assets']);
    }

    public function enqueue_assets() {
        wp_register_style('cubag-connector-css', false);
        wp_enqueue_style('cubag-connector-css');
        wp_add_inline_style('cubag-connector-css', self::get_inline_css());
    }

    /**
     * Helper to make cached API GET requests
     */
    private function fetch_api($endpoint, $cache_key, $ttl = self::CACHE_TTL) {
        $cached = get_transient($cache_key);
        if ($cached !== false) {
            return $cached;
        }

        $url = self::API_BASE . $endpoint;
        $response = wp_remote_get($url, [
            'timeout' => 10,
            'headers' => [
                'Accept'     => 'application/json',
                'User-Agent' => 'CUBAG-WordPress-Plugin/1.0.0 (' . home_url() . ')',
            ],
        ]);

        if (is_wp_error($response)) {
            return null;
        }

        $code = wp_remote_retrieve_response_code($response);
        if ($code !== 200) {
            return null;
        }

        $data = json_decode(wp_remote_retrieve_body($response), true);
        if ($data) {
            set_transient($cache_key, $data, $ttl);
        }
        return $data;
    }

    // ─────────────────────────────────────────────────────────────
    // 1. MEMBERS IN GOOD STANDING [cubag_members]
    // ─────────────────────────────────────────────────────────────
    public function render_members($atts) {
        $atts = shortcode_atts([
            'limit' => 50,
            'port'  => '',
            'search' => 'yes',
        ], $atts);

        $data = $this->fetch_api('/members', 'cubag_members_list', 300);
        $members = is_array($data) ? $data : [];

        if (!empty($atts['port'])) {
            $port_filter = strtolower(trim($atts['port']));
            $members = array_filter($members, function($m) use ($port_filter) {
                return strpos(strtolower($m['primary_port'] ?? ''), $port_filter) !== false;
            });
        }

        if (intval($atts['limit']) > 0) {
            $members = array_slice($members, 0, intval($atts['limit']));
        }

        ob_start();
        ?>
        <div class="cubag-wrap">
            <?php if ($atts['search'] === 'yes'): ?>
                <div class="cubag-search-box">
                    <input type="text" id="cubag-member-filter" placeholder="Search member company, license, or port..." onkeyup="cubagFilterMembers()">
                </div>
            <?php endif; ?>

            <div class="cubag-members-grid" id="cubag-members-container">
                <?php if (empty($members)): ?>
                    <p class="cubag-muted">No accredited members found at this time.</p>
                <?php else: ?>
                    <?php foreach ($members as $m): 
                        $name = esc_html($m['company'] ?? $m['name'] ?? 'Licensed Broker');
                        $contact = esc_html($m['name'] ?? '');
                        $num = esc_html($m['membership_number'] ?? '');
                        $port = esc_html($m['primary_port'] ?? 'Tema Port');
                        $type = esc_html($m['member_type'] ?? 'Corporate');
                        $score = esc_html($m['compliance_score'] ?? '100');
                        $stars = esc_html($m['star_rating'] ?? '5.0');
                        $photo = !empty($m['profile_photo']) ? esc_url($m['profile_photo']) : '';
                    ?>
                        <div class="cubag-member-card" data-search="<?php echo esc_attr(strtolower("$name $contact $num $port $type")); ?>">
                            <div class="cubag-member-head">
                                <?php if ($photo): ?>
                                    <img src="<?php echo $photo; ?>" alt="<?php echo $name; ?>" class="cubag-avatar">
                                <?php else: ?>
                                    <div class="cubag-avatar-placeholder"><?php echo strtoupper(substr($name, 0, 2)); ?></div>
                                <?php endif; ?>
                                <div>
                                    <h4 class="cubag-title"><?php echo $name; ?></h4>
                                    <span class="cubag-badge cubag-badge-green">✓ Good Standing</span>
                                </div>
                            </div>
                            <div class="cubag-meta-list">
                                <div class="cubag-meta-item"><span class="cubag-meta-label">Member No:</span> <strong><?php echo $num; ?></strong></div>
                                <div class="cubag-meta-item"><span class="cubag-meta-label">Category:</span> <?php echo $type; ?></div>
                                <div class="cubag-meta-item"><span class="cubag-meta-label">Port Base:</span> <?php echo $port; ?></div>
                                <div class="cubag-meta-item"><span class="cubag-meta-label">Rating:</span> ⭐ <?php echo $stars; ?> (Score: <?php echo $score; ?>%)</div>
                            </div>
                        </div>
                    <?php endforeach; ?>
                <?php endif; ?>
            </div>
        </div>
        <script>
        function cubagFilterMembers() {
            var val = document.getElementById('cubag-member-filter').value.toLowerCase();
            var cards = document.querySelectorAll('.cubag-member-card');
            cards.forEach(function(c) {
                var search = c.getAttribute('data-search') || '';
                c.style.display = search.includes(val) ? '' : 'none';
            });
        }
        </script>
        <?php
        return ob_get_clean();
    }

    // ─────────────────────────────────────────────────────────────
    // 2. MEMBER VERIFICATION BOX [cubag_verify_member]
    // ─────────────────────────────────────────────────────────────
    public function render_verify_member() {
        ob_start();
        ?>
        <div class="cubag-wrap cubag-verify-box">
            <h3>Verify CUBAG Broker Accreditation</h3>
            <p class="cubag-muted">Check if a customs clearing agent or freight forwarding firm is in Good Standing.</p>
            <div class="cubag-verify-form">
                <input type="text" id="cubag-verify-input" placeholder="Enter Company Name or Member No (e.g. CUBAG-2026-009)...">
                <button type="button" id="cubag-verify-btn" onclick="cubagPerformVerify()">Verify Broker</button>
            </div>
            <div id="cubag-verify-result" style="display:none;" class="cubag-verify-result"></div>
        </div>
        <script>
        function cubagPerformVerify() {
            var q = document.getElementById('cubag-verify-input').value.trim();
            var resDiv = document.getElementById('cubag-verify-result');
            var btn = document.getElementById('cubag-verify-btn');
            if (!q || q.length < 3) {
                alert('Please enter at least 3 characters.');
                return;
            }
            btn.disabled = true;
            btn.innerText = 'Verifying...';
            resDiv.style.display = 'block';
            resDiv.innerHTML = '<p class="cubag-loading">Querying official CUBAG accreditation register...</p>';

            fetch('https://cubag-api-server.fly.dev/api/v1/public/verify-member?query=' + encodeURIComponent(q))
                .then(function(r){ return r.json(); })
                .then(function(data){
                    btn.disabled = false;
                    btn.innerText = 'Verify Broker';
                    if (data.verified) {
                        resDiv.innerHTML = '<div class="cubag-alert-box cubag-alert-success">' +
                            '<h4>✓ Official Member in Good Standing</h4>' +
                            '<p><strong>Company:</strong> ' + (data.company_name || '-') + '</p>' +
                            '<p><strong>Membership No:</strong> ' + (data.membership_number || '-') + '</p>' +
                            '<p><strong>Category:</strong> ' + (data.member_category || '-') + '</p>' +
                            '<p><strong>Primary Port:</strong> ' + (data.primary_port || '-') + '</p>' +
                            '<p><strong>Accreditation Valid Until:</strong> ' + (data.valid_until || 'Active') + '</p>' +
                        '</div>';
                    } else {
                        resDiv.innerHTML = '<div class="cubag-alert-box cubag-alert-danger">' +
                            '<h4>✕ Accreditation Not Found</h4>' +
                            '<p>' + (data.message || 'No member in good standing matches this query.') + '</p>' +
                        '</div>';
                    }
                })
                .catch(function(err){
                    btn.disabled = false;
                    btn.innerText = 'Verify Broker';
                    resDiv.innerHTML = '<div class="cubag-alert-box cubag-alert-danger"><p>Network error connecting to verification server.</p></div>';
                });
        }
        </script>
        <?php
        return ob_get_clean();
    }

    // ─────────────────────────────────────────────────────────────
    // 3. UPCOMING EVENTS & WORKSHOPS [cubag_events]
    // ─────────────────────────────────────────────────────────────
    public function render_events($atts) {
        $atts = shortcode_atts(['limit' => 6], $atts);
        $data = $this->fetch_api('/events', 'cubag_events_data', 180);
        $events = is_array($data) && isset($data['items']) ? $data['items'] : [];
        if (intval($atts['limit']) > 0) {
            $events = array_slice($events, 0, intval($atts['limit']));
        }

        ob_start();
        ?>
        <div class="cubag-wrap">
            <div class="cubag-events-grid">
                <?php if (empty($events)): ?>
                    <p class="cubag-muted">No upcoming events scheduled at the moment.</p>
                <?php else: ?>
                    <?php foreach ($events as $ev): 
                        $title = esc_html($ev['title'] ?? 'Event');
                        $desc = esc_html($ev['description'] ?? '');
                        $date = esc_html($ev['date'] ?? '');
                        $time = esc_html($ev['time'] ?? '');
                        $loc = esc_html($ev['location'] ?? 'Tema Port');
                    ?>
                        <div class="cubag-card cubag-event-card">
                            <div class="cubag-event-date-badge">
                                <strong>📅 <?php echo $date; ?></strong><?php if ($time) echo ' • ' . $time; ?>
                            </div>
                            <h4 class="cubag-title"><?php echo $title; ?></h4>
                            <p class="cubag-desc"><?php echo $desc; ?></p>
                            <div class="cubag-card-footer">
                                <span>📍 <?php echo $loc; ?></span>
                            </div>
                        </div>
                    <?php endforeach; ?>
                <?php endif; ?>
            </div>
        </div>
        <?php
        return ob_get_clean();
    }

    // ─────────────────────────────────────────────────────────────
    // 4. MARITIME & TRADE NEWS [cubag_news]
    // ─────────────────────────────────────────────────────────────
    public function render_news($atts) {
        $atts = shortcode_atts(['limit' => 6], $atts);
        $data = $this->fetch_api('/news', 'cubag_news_data', 180);
        $items = is_array($data) && isset($data['items']) ? $data['items'] : (is_array($data) ? $data : []);
        if (intval($atts['limit']) > 0) {
            $items = array_slice($items, 0, intval($atts['limit']));
        }

        ob_start();
        ?>
        <div class="cubag-wrap">
            <div class="cubag-news-grid">
                <?php if (empty($items)): ?>
                    <p class="cubag-muted">No news releases available at this time.</p>
                <?php else: ?>
                    <?php foreach ($items as $item): 
                        $title = esc_html($item['title'] ?? '');
                        $summary = esc_html($item['summary'] ?? $item['content'] ?? '');
                        $img = !empty($item['image_url']) ? esc_url($item['image_url']) : '';
                        $date = esc_html($item['published_at'] ?? $item['created_at'] ?? '');
                    ?>
                        <div class="cubag-card cubag-news-card">
                            <?php if ($img): ?>
                                <div class="cubag-news-thumb" style="background-image:url('<?php echo $img; ?>');"></div>
                            <?php endif; ?>
                            <div class="cubag-card-body">
                                <span class="cubag-news-date"><?php echo substr($date, 0, 10); ?></span>
                                <h4 class="cubag-title"><?php echo $title; ?></h4>
                                <p class="cubag-desc"><?php echo wp_trim_words($summary, 22); ?></p>
                            </div>
                        </div>
                    <?php endforeach; ?>
                <?php endif; ?>
            </div>
        </div>
        <?php
        return ob_get_clean();
    }

    // ─────────────────────────────────────────────────────────────
    // 5. PORT OPERATIONAL BULLETINS / ALERTS [cubag_bulletins]
    // ─────────────────────────────────────────────────────────────
    public function render_bulletins() {
        $data = $this->fetch_api('/bulletins', 'cubag_bulletins_data', 60);
        $items = is_array($data) && isset($data['bulletins']) ? $data['bulletins'] : (is_array($data) ? $data : []);

        ob_start();
        ?>
        <div class="cubag-wrap">
            <div class="cubag-bulletins-list">
                <?php if (empty($items)): ?>
                    <p class="cubag-muted">All ports operating normally.</p>
                <?php else: ?>
                    <?php foreach ($items as $b): 
                        $port = esc_html($b['port_name'] ?? 'Port');
                        $status = esc_html($b['status'] ?? 'Operational');
                        $notice = esc_html($b['notice'] ?? '');
                        $color = esc_attr($b['status_color'] ?? '#2E7D32');
                    ?>
                        <div class="cubag-bulletin-row">
                            <div class="cubag-bulletin-port">
                                <span class="cubag-status-dot" style="background-color:<?php echo $color; ?>;"></span>
                                <strong><?php echo $port; ?></strong>
                            </div>
                            <div class="cubag-bulletin-notice">
                                <?php echo $notice; ?>
                            </div>
                            <div class="cubag-bulletin-badge" style="color:<?php echo $color; ?>; border-color:<?php echo $color; ?>;">
                                <?php echo $status; ?>
                            </div>
                        </div>
                    <?php endforeach; ?>
                <?php endif; ?>
            </div>
        </div>
        <?php
        return ob_get_clean();
    }

    // ─────────────────────────────────────────────────────────────
    // 6. CTI TRAINING COURSES [cubag_courses]
    // ─────────────────────────────────────────────────────────────
    public function render_courses() {
        $data = $this->fetch_api('/courses', 'cubag_courses_data', 300);
        $items = is_array($data) && isset($data['items']) ? $data['items'] : [];

        ob_start();
        ?>
        <div class="cubag-wrap">
            <div class="cubag-courses-grid">
                <?php if (empty($items)): ?>
                    <p class="cubag-muted">No courses currently enrolling.</p>
                <?php else: ?>
                    <?php foreach ($items as $c): 
                        $title = esc_html($c['title'] ?? 'Course');
                        $duration = esc_html($c['duration'] ?? '4 Weeks');
                        $mode = esc_html($c['mode'] ?? 'Hybrid');
                        $date = esc_html($c['start_date'] ?? 'Upcoming');
                        $desc = esc_html($c['description'] ?? '');
                        $fee = floatval($c['fee'] ?? 0);
                    ?>
                        <div class="cubag-card cubag-course-card">
                            <div class="cubag-badge cubag-badge-blue"><?php echo $mode; ?> • <?php echo $duration; ?></div>
                            <h4 class="cubag-title"><?php echo $title; ?></h4>
                            <p class="cubag-desc"><?php echo $desc; ?></p>
                            <div class="cubag-course-footer">
                                <div><strong>Starts:</strong> <?php echo $date; ?></div>
                                <div class="cubag-course-fee"><?php echo $fee > 0 ? 'GH₵ ' . number_format($fee, 2) : 'Sponsored / Contact CTI'; ?></div>
                            </div>
                        </div>
                    <?php endforeach; ?>
                <?php endif; ?>
            </div>
        </div>
        <?php
        return ob_get_clean();
    }

    // ─────────────────────────────────────────────────────────────
    // 7. BANK OF GHANA EXCHANGE RATES TICKER [cubag_rates]
    // ─────────────────────────────────────────────────────────────
    public function render_exchange_rates() {
        $summary = $this->fetch_api('/portal-summary', 'cubag_portal_summary_data', 60);
        $rates = $summary['exchange_rates'] ?? [];

        if (empty($rates)) return '';

        ob_start();
        ?>
        <div class="cubag-rates-ticker">
            <span class="cubag-rates-label">Bank of Ghana Indicative Rates:</span>
            <span class="cubag-rate-pill">USD: GH₵ <?php echo number_format(floatval($rates['usd_ghs'] ?? 0), 2); ?></span>
            <span class="cubag-rate-pill">EUR: GH₵ <?php echo number_format(floatval($rates['eur_ghs'] ?? 0), 2); ?></span>
            <span class="cubag-rate-pill">GBP: GH₵ <?php echo number_format(floatval($rates['gbp_ghs'] ?? 0), 2); ?></span>
            <span class="cubag-rate-pill">CNY: GH₵ <?php echo number_format(floatval($rates['cny_ghs'] ?? 0), 2); ?></span>
        </div>
        <?php
        return ob_get_clean();
    }

    // ─────────────────────────────────────────────────────────────
    // 8. ALL-IN-ONE HOMEPAGE PORTAL SUMMARY [cubag_portal_summary]
    // ─────────────────────────────────────────────────────────────
    public function render_portal_summary() {
        $summary = $this->fetch_api('/portal-summary', 'cubag_portal_summary_data', 60);
        if (!$summary) return '<p class="cubag-muted">CUBAG portal data is temporarily unavailable.</p>';

        $stats = $summary['stats'] ?? [];
        ob_start();
        ?>
        <div class="cubag-wrap">
            <div class="cubag-stats-row">
                <div class="cubag-stat-box">
                    <span class="cubag-stat-num"><?php echo esc_html($stats['active_members'] ?? '0'); ?></span>
                    <span class="cubag-stat-label">Active Members in Good Standing</span>
                </div>
                <div class="cubag-stat-box">
                    <span class="cubag-stat-num"><?php echo esc_html($stats['licensed_brokers'] ?? '0'); ?></span>
                    <span class="cubag-stat-label">Licensed Customs Brokers</span>
                </div>
                <div class="cubag-stat-box">
                    <span class="cubag-stat-num"><?php echo esc_html($stats['operating_ports'] ?? '6'); ?></span>
                    <span class="cubag-stat-label">Ports of Operation</span>
                </div>
                <div class="cubag-stat-box">
                    <span class="cubag-stat-num"><?php echo esc_html($stats['cti_courses'] ?? '3'); ?></span>
                    <span class="cubag-stat-label">CTI Training Programs</span>
                </div>
            </div>
            <?php echo $this->render_exchange_rates(); ?>
        </div>
        <?php
        return ob_get_clean();
    }

    // ─────────────────────────────────────────────────────────────
    // INLINE CSS STYLING
    // ─────────────────────────────────────────────────────────────
    private static function get_inline_css() {
        return "
        .cubag-wrap { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 20px 0; color: #1a1a1a; }
        .cubag-muted { color: #666; font-size: 14px; }
        .cubag-search-box input, .cubag-verify-form input { width: 100%; max-width: 480px; padding: 10px 14px; border: 1px solid #ccc; border-radius: 6px; font-size: 14px; margin-bottom: 16px; box-sizing: border-box; }
        .cubag-members-grid, .cubag-events-grid, .cubag-news-grid, .cubag-courses-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 18px; margin-top: 12px; }
        .cubag-member-card, .cubag-card { background: #fff; border: 1px solid #e5e5e5; border-radius: 8px; padding: 18px; box-shadow: 0 2px 4px rgba(0,0,0,0.04); transition: transform 0.2s, box-shadow 0.2s; }
        .cubag-member-card:hover, .cubag-card:hover { transform: translateY(-2px); box-shadow: 0 4px 10px rgba(0,0,0,0.08); }
        .cubag-member-head { display: flex; align-items: center; gap: 12px; margin-bottom: 12px; }
        .cubag-avatar { width: 44px; height: 44px; border-radius: 50%; object-fit: cover; }
        .cubag-avatar-placeholder { width: 44px; height: 44px; border-radius: 50%; background: #6B3E26; color: #fff; display: flex; align-items: center; justify-content: center; font-weight: bold; font-size: 14px; }
        .cubag-title { margin: 0 0 4px 0; font-size: 16px; font-weight: 700; color: #111; line-height: 1.3; }
        .cubag-desc { font-size: 13.5px; color: #555; margin: 8px 0 12px; line-height: 1.4; }
        .cubag-badge { display: inline-block; font-size: 11px; font-weight: 600; padding: 3px 8px; border-radius: 12px; }
        .cubag-badge-green { background: #E8F5E9; color: #2E7D32; }
        .cubag-badge-blue { background: #E3F2FD; color: #0288D1; }
        .cubag-meta-list { font-size: 13px; line-height: 1.7; color: #444; border-top: 1px solid #f0f0f0; padding-top: 10px; }
        .cubag-meta-label { color: #888; margin-right: 4px; }
        .cubag-verify-box { background: #fdfaf7; border: 1px solid #e0d8cf; border-radius: 10px; padding: 24px; max-width: 600px; margin: 24px auto; }
        .cubag-verify-form { display: flex; gap: 8px; margin: 16px 0; flex-wrap: wrap; }
        .cubag-verify-form input { flex: 1; min-width: 240px; margin-bottom: 0; }
        .cubag-verify-form button { background: #E89A3C; color: #fff; border: none; padding: 10px 20px; font-size: 14px; font-weight: bold; border-radius: 6px; cursor: pointer; }
        .cubag-verify-form button:hover { background: #d78829; }
        .cubag-alert-box { padding: 14px; border-radius: 6px; margin-top: 14px; font-size: 14px; }
        .cubag-alert-success { background: #E8F5E9; border: 1px solid #A5D6A7; color: #1B5E20; }
        .cubag-alert-danger { background: #FFEBEE; border: 1px solid #FFCDD2; color: #B71C1C; }
        .cubag-news-thumb { height: 140px; background-size: cover; background-position: center; border-radius: 6px; margin-bottom: 12px; }
        .cubag-news-date { font-size: 11px; text-transform: uppercase; color: #888; font-weight: 600; display: block; margin-bottom: 4px; }
        .cubag-bulletins-list { display: flex; flex-direction: column; gap: 8px; }
        .cubag-bulletin-row { display: flex; align-items: center; justify-content: space-between; background: #fff; border: 1px solid #eee; padding: 12px 16px; border-radius: 6px; gap: 14px; font-size: 13.5px; }
        .cubag-bulletin-port { display: flex; align-items: center; gap: 8px; min-width: 160px; }
        .cubag-status-dot { width: 10px; height: 10px; border-radius: 50%; display: inline-block; }
        .cubag-bulletin-notice { flex: 1; color: #555; }
        .cubag-bulletin-badge { font-size: 11.5px; font-weight: 700; padding: 2px 8px; border: 1px solid; border-radius: 4px; text-transform: uppercase; white-space: nowrap; }
        .cubag-rates-ticker { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; background: #1F1612; color: #fff; padding: 10px 16px; border-radius: 6px; font-size: 13px; margin: 16px 0; }
        .cubag-rates-label { font-weight: 700; color: #E89A3C; }
        .cubag-rate-pill { background: rgba(255,255,255,0.1); padding: 3px 8px; border-radius: 4px; }
        .cubag-stats-row { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; margin-bottom: 16px; }
        .cubag-stat-box { background: #fff; border: 1px solid #e5e5e5; border-radius: 8px; padding: 16px; text-align: center; }
        .cubag-stat-num { font-size: 28px; font-weight: 800; color: #6B3E26; display: block; }
        .cubag-stat-label { font-size: 12px; color: #666; margin-top: 4px; display: block; font-weight: 600; }
        .cubag-course-footer { display: flex; justify-content: space-between; align-items: center; border-top: 1px solid #eee; padding-top: 10px; margin-top: 10px; font-size: 13px; }
        .cubag-course-fee { font-weight: 700; color: #2E7D32; }
        ";
    }
}

new CUBAG_Portal_Connector();
