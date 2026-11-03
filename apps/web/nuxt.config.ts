export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: false },
  modules: ['@pinia/nuxt', '@nuxtjs/color-mode'],
  colorMode: {
    preference: 'system',
    fallback: 'dark',
    classSuffix: '',
  },
  css: ['~/assets/css/main.css'],
  typescript: {
    strict: true,
    typeCheck: true,
  },
  nitro: {
    preset: 'static',
  },
  app: {
    head: {
      title: 'Cadenza Remote',
      meta: [
        {
          name: 'description',
          content: 'A local controller for the music playing on Cadenza Host.',
        },
        { name: 'theme-color', content: '#111315' },
      ],
    },
  },
});
