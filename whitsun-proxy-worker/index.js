/**
 * Clean Cloudflare Worker Reverse Proxy for WhitsunPay
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

    const url = new URL(request.url);
    const targetUrl = `https://developer.whitsun.dev${url.pathname}${url.search}`;

    // Pass only legitimate clean API headers (no spoofed Origin or Referer)
    const cleanHeaders = new Headers();
    cleanHeaders.set('Content-Type', 'application/json');
    cleanHeaders.set('Accept', 'application/json');
    cleanHeaders.set('User-Agent', 'CUBAG-Server/2.0 (Ghana Customs Platform)');

    const clientId = request.headers.get('x-client-id');
    if (clientId) cleanHeaders.set('x-client-id', clientId);

    const apiKey = request.headers.get('x-api-key');
    if (apiKey) cleanHeaders.set('x-api-key', apiKey);

    const callbackUrl = request.headers.get('x-callback-url');
    if (callbackUrl) cleanHeaders.set('x-callback-url', callbackUrl);

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
