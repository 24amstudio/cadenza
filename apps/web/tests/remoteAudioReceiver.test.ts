import { expect, test } from 'bun:test';
import { lanAudioSocketUrl } from '../app/lib/host/endpoint';

test('the Wi-Fi audio socket dials the Host address, not its Bonjour name', () => {
  expect(
    lanAudioSocketUrl({
      address: '192.168.1.5',
      name: 'darrells-macbook-air.local',
      port: 43129,
    }),
  ).toBe('ws://192.168.1.5:43129/v1/socket');
});
