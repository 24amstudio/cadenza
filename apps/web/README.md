# Cadenza Remote Web

The browser controller foundation described in `cadenza-remote-web-prd.md`.

This Nuxt 4 app is statically generated and designed to be served by Cadenza Host. The current UI uses an in-memory snapshot so the responsive shell can be reviewed before the Swift WebRemoteService is available. `types/protocol.ts` keeps the browser transport boundary explicit for WebRTC, WebSocket, SSE, and Bluetooth GATT adapters.

## Local development

```sh
bun install
bun run dev
```

Build the static bundle with `bun run generate`. Host integration must add the generated output to `apps/host/Resources/WebRemote/` and provide the authenticated HTTP, WebSocket, WebRTC signaling, and BLE boundaries described in the PRD.
