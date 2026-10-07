window.__ModuleLoader__.load({
  id: '@aisland/deepseek-harness-plugin',
  factory() {
    return {
      inject: ['connection', 'uiWorkspace'],
      apply(ctx) {
        ctx.effect(() => {
          const abort = new AbortController(); let timer;
          const schedule = delay => { if (!abort.signal.aborted) timer = setTimeout(poll, delay); };
          async function poll() {
            let delay = 500;
            try {
              const result = await ctx.connection.rpc.call('/aisland-deepseek', 'poll', {}, abort.signal);
              if (abort.signal.aborted) return;
              if (result.ok) {
                delay = result.value.poll_interval_ms;
                const request = result.value.request;
                if (request) {
                  let status = 'dispatched';
                  try { ctx.uiWorkspace.openSession(request.session_id); } catch { status = 'failed'; }
                  // Public openSession returns void; this proves dispatch, not visible/frontmost acceptance.
                  await ctx.connection.rpc.call('/aisland-deepseek', 'ack', {
                    request_id: request.request_id, session_id: request.session_id,
                    profile_id: request.profile_id, status,
                  }, abort.signal);
                }
              }
            } catch { /* Host replacement/disconnect must not disturb the source UI. */ }
            schedule(delay);
          }
          void poll();
          return () => { abort.abort(); clearTimeout(timer); };
        });
      },
    };
  },
});
