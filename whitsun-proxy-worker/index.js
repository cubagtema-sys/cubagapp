/**
 * Cloudflare Worker Reverse Proxy for WhitsunPay.
 *
 * The WhitsunPay credentials live ONLY here as Worker secrets — they are never
 * shipped inside the mobile/web client. The client calls this worker without any
 * API key; the worker injects x-client-id / x-api-key / x-callback-url server-side.
 *
 * Set the secrets once with:
 *   wrangler secret put WHITSUNPAY_CLIENT_ID
 *   wrangler secret put WHITSUNPAY_API_KEY
 *   wrangler secret put WHITSUNPAY_CALLBACK_URL
 */
export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': '*',
          'Access-Control-Max-Age': '86400',
        },
      });
    }

    const targetOrigin = env.TARGET_ORIGIN || 'https://developer.whitsun.dev';
    const clientId = env.WHITSUNPAY_CLIENT_ID;
    const apiKey = env.WHITSUNPAY_API_KEY;

    // Fail closed: never proxy without server-side credentials configured.
    if (!clientId || !apiKey) {
      return new Response(
        JSON.stringify({ error: 'Worker WhitsunPay credentials are not configured' }),
        {
          status: 500,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          },
        }
      );
    }

    const url = new URL(request.url);
    const targetUrl = `${targetOrigin}${url.pathname}${url.search}`;

    // Build clean headers. Credentials are injected from Worker secrets — any
    // client-supplied x-api-key / x-client-id / x-callback-url is ignored.
    const cleanHeaders = new Headers();
    cleanHeaders.set('Content-Type', 'application/json');
    cleanHeaders.set('Accept', 'application/json');
    cleanHeaders.set('User-Agent', 'CUBAG-Server/2.0 (Ghana Customs Platform)');
    cleanHeaders.set('x-client-id', clientId);
    cleanHeaders.set('x-api-key', apiKey);
    if (env.WHITSUNPAY_CALLBACK_URL) {
      cleanHeaders.set('x-callback-url', env.WHITSUNPAY_CALLBACK_URL);
    }

    const hasBody = request.method !== 'GET' && request.method !== 'HEAD';
    const body = hasBody ? await request.text() : undefined;

    try {
      const response = await fetch(targetUrl, {
        method: request.method,
        headers: cleanHeaders,
        body: body,
      });

      const responseHeaders = new Headers(response.headers);
      responseHeaders.set('Access-Control-Allow-Origin', '*');
      responseHeaders.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
      responseHeaders.set('Access-Control-Allow-Headers', '*');

      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: responseHeaders,
      });
    } catch (err) {
      return new Response(
        JSON.stringify({ error: err.message, target: targetUrl }),
        {
          status: 502,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          },
        }
      );
    }
  },
};
