import Schema from '@deepseek-ai/schemastery';
import { attachHost } from './core.mjs';
export const name = 'aisland-deepseek';
export const inject = ['sessions', 'connection'];
export const Config = Schema.object({
  profileID: Schema.string().default('desktop'),
  bridgeSocketPath: Schema.string().default(''),
  navigationSocketPath: Schema.string().default(''),
  bridgeTimeoutMs: Schema.number().min(10).max(2000).default(200),
  navigationTimeoutMs: Schema.number().min(100).max(10000).default(2000),
  pollIntervalMs: Schema.number().min(50).max(5000).default(500),
});
export function apply(ctx, config) { attachHost(ctx, config); }
