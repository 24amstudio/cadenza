import { describe, expect, test } from 'bun:test';
import { parseStoredCredential } from '../app/lib/host/credentials';
import {
  lanEndpointFrom,
  lanSocketUrls,
  type LanEndpoint,
} from '../app/lib/host/endpoint';
import { LanFirstHostClient } from '../app/lib/host/lanFirstClient';
import {
  MemoryCredentials,
  harness,
  remoteId,
  socketAt,
  token,
  welcome,
} from './support/hostClient';

const lan: LanEndpoint = {
  address: '192.168.1.20',
  name: 'my-mac.local',
  port: 43129,
};

const nameUrl = 'ws://my-mac.local:43129/v1/socket';
const addressUrl = 'ws://192.168.1.20:43129/v1/socket';

function lanHarness(credentials: MemoryCredentials) {
  return harness(
    credentials,
    false,
    (options) => new LanFirstHostClient(options),
  );
}

function pairedWithLan(): MemoryCredentials {
  const credentials = new MemoryCredentials();
  credentials.value = {
    remoteId,
    token,
    name: 'Web browser on Mac',
    lastCreditSequence: 0,
    lan,
  };

  return credentials;
}

describe('LanFirstHostClient', () => {
  test('tries the Bonjour name first and keeps reconnecting to it after a welcome', () => {
    const { client, sockets, clock } = lanHarness(pairedWithLan());
    let fallbacks = 0;

    client.connectOverLan(() => {
      fallbacks += 1;
    });
    expect(socketAt(sockets, 0).url).toBe(nameUrl);

    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token, undefined, lan));
    socketAt(sockets, 0).serverDrop();
    clock.advance(1_000);

    expect(socketAt(sockets, 1).url).toBe(nameUrl);
    expect(fallbacks).toBe(0);
  });

  test('moves to the recorded address when the name fails, then to Bluetooth when both fail', () => {
    const { client, sockets, clock } = lanHarness(pairedWithLan());
    let fallbacks = 0;

    client.connectOverLan(() => {
      fallbacks += 1;
    });
    socketAt(sockets, 0).serverDrop();

    expect(socketAt(sockets, 1).url).toBe(addressUrl);
    expect(fallbacks).toBe(0);

    socketAt(sockets, 1).serverDrop();
    clock.advance(60_000);

    expect(fallbacks).toBe(1);
    expect(sockets).toHaveLength(2);
  });

  test('gives up on a silent LAN address within the attempt window', () => {
    const { client, sockets, clock } = lanHarness(pairedWithLan());
    let fallbacks = 0;

    client.connectOverLan(() => {
      fallbacks += 1;
    });
    clock.advance(6_000);

    expect(socketAt(sockets, 0).closed).toBe(true);
    expect(socketAt(sockets, 1).url).toBe(addressUrl);
    expect(fallbacks).toBe(1);
  });

  test('after a welcome, a failed reconnect moves on to the recorded address', () => {
    const { client, sockets, clock } = lanHarness(pairedWithLan());

    client.connectOverLan(() => {});
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token, undefined, lan));
    socketAt(sockets, 0).serverDrop();
    clock.advance(1_000);
    socketAt(sockets, 1).serverDrop();
    clock.advance(2_000);

    expect(socketAt(sockets, 2).url).toBe(addressUrl);
  });

  test('records the Host address from each welcome and forgets it when none is offered', () => {
    const credentials = new MemoryCredentials();
    credentials.value = {
      remoteId,
      token,
      name: 'Web browser on Mac',
      lastCreditSequence: 0,
    };
    const { client, sockets, clock } = lanHarness(credentials);

    client.start(null);
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token, undefined, lan));
    expect(credentials.value?.lan).toEqual(lan);

    const moved = { ...lan, address: '192.168.1.30' };
    socketAt(sockets, 0).receive(welcome(token, undefined, moved));
    expect(credentials.value?.lan).toEqual(moved);

    socketAt(sockets, 0).serverDrop();
    clock.advance(1_000);
    socketAt(sockets, 1).open();
    socketAt(sockets, 1).receive(welcome(token));
    expect(credentials.value?.lan).toBeNull();
  });
});

describe('LAN endpoint validation', () => {
  test('keeps an IPv4 address with a valid port and a Bonjour name', () => {
    expect(lanEndpointFrom('192.168.1.20', 'my-mac.local', 43129)).toEqual(lan);
    expect(
      lanEndpointFrom('192.168.1.20', 'my-mac.example.com', 43129),
    ).toEqual({
      address: '192.168.1.20',
      name: null,
      port: 43129,
    });
    expect(lanEndpointFrom('mac.local', 'mac.local', 43129)).toBeNull();
    expect(lanEndpointFrom('192.168.1.256', null, 43129)).toBeNull();
    expect(lanEndpointFrom('192.168.1.20', null, 0)).toBeNull();
    expect(lanEndpointFrom(null, 'my-mac.local', 43129)).toBeNull();
  });

  test('tries the name before the address', () => {
    expect(lanSocketUrls(lan)).toEqual([nameUrl, addressUrl]);
    expect(lanSocketUrls({ ...lan, name: null })).toEqual([addressUrl]);
  });

  test('drops a damaged stored endpoint and keeps the credential', () => {
    const text = JSON.stringify({
      remoteId,
      token,
      name: 'Web browser on Mac',
      lastCreditSequence: 0,
      lan: { address: 'mac.local', port: 43129 },
    });

    const parsed = parseStoredCredential(text);

    expect(parsed).toMatchObject({ remoteId, token });
    expect(parsed?.lan).toBeUndefined();
  });
});
