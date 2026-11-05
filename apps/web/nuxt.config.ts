// Cadenza Remote Web is a client-rendered single-page app. `nuxt generate` emits only static files that Cadenza Host
// serves; no server bundle or server-side rendering runs at runtime.
export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  ssr: false,
  devtools: { enabled: false },
  modules: ['@pinia/nuxt'],
  css: ['~/assets/css/tokens.css', '~/assets/css/base.css'],
  typescript: {
    strict: true,
    typeCheck: true,
  },
  nitro: {
    preset: 'static',
  },
  app: {
    // Cadenza Host serves the app at the root. GitHub Pages project sites serve it under /<repository>/, which the
    // Pages workflow passes in as CADENZA_WEB_BASE_URL.
    baseURL: process.env['CADENZA_WEB_BASE_URL'] ?? '/',
    head: {
      title: 'Cadenza Remote',
      htmlAttrs: { lang: 'en' },
      meta: [
        {
          name: 'viewport',
          content: 'width=device-width, initial-scale=1, viewport-fit=cover',
        },
        {
          name: 'description',
          content: 'Control the music playing on your Cadenza Host.',
        },
        { name: 'referrer', content: 'no-referrer' },
      ],
    },
  },
});
