import { assertEquals, assertThrows } from '@std/assert';
import { HttpError } from '../http.ts';
import { normalizeMsisdn } from './service.ts';

Deno.test('numéro mobile money normalisé en 243XXXXXXXXX', () => {
  for (const input of ['0812345678', '812345678', '+243812345678', '243812345678', '00243 81 234 56 78']) {
    assertEquals(normalizeMsisdn(input), '243812345678');
  }
  for (const bad of ['', '12345', '0112345678', '+33612345678']) {
    assertThrows(() => normalizeMsisdn(bad), HttpError);
  }
});
