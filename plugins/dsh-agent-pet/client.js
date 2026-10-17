/** agent-pet for DeepSeek Harness, client half: drains the host's loopback queue and runs open-session / new-chat in the UI. */
window.__ModuleLoader__.load({
  id: 'dsh-agent-pet',
  factory() {
    const PORT_CANDIDATES = [50399, 50400, 50401];
    const SERVICE = 'agent-pet';
    const POLL_MS = 400;
    const DISCOVER_MS = 3000;
    const HIDDEN_POLL_MS = 1500;
    const REQUEST_TIMEOUT_MS = 2000;
    const FIRST_POLL_DELAY_MS = 600;

    async function fetchJson(url) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
      try {
        const response = await fetch(url, { signal: controller.signal, cache: 'no-store' });
        if (!response.ok) throw new Error(`bridge answered ${response.status}`);
        return await response.json();
      } finally {
        clearTimeout(timer);
      }
    }

    async function discoverPort() {
      for (const port of PORT_CANDIDATES) {
        try {
          const body = await fetchJson(`http://127.0.0.1:${port}/health`);
          if (body && body.service === SERVICE) return port;
        } catch {
          /* this port is not ours — try the next one */
        }
      }
      return null;
    }

    return {
      inject: ['uiWorkspace'],

      apply(ctx) {
        const execute = (type, sessionId) => {
          if (type === 'new-chat') ctx.uiWorkspace.startSession();
          else if (type === 'open-session' && sessionId) ctx.uiWorkspace.openSession(sessionId);
        };

        ctx.effect(() => {
          let stopped = false;
          let timer = null;
          let port = null;

          const schedule = (delay) => {
            if (!stopped) timer = setTimeout(tick, delay);
          };

          const tick = async () => {
            if (stopped) return;
            // Only the visible tab answers, so two open windows do not both act on one click.
            if (document.visibilityState !== 'visible') return schedule(HIDDEN_POLL_MS);
            if (port === null) {
              port = await discoverPort();
              if (port === null) return schedule(DISCOVER_MS);
            }
            let commands;
            try {
              const body = await fetchJson(`http://127.0.0.1:${port}/cmd`);
              commands = Array.isArray(body && body.commands) ? body.commands : [];
            } catch {
              port = null; // the host half restarted or moved: rediscover next tick
              return schedule(DISCOVER_MS);
            }
            for (const command of commands) {
              try {
                execute(command && command.type, command && command.sessionId);
              } catch (error) {
                console.warn('[agent-pet] command failed', command, error);
              }
            }
            schedule(POLL_MS);
          };

          schedule(FIRST_POLL_DELAY_MS);
          return () => {
            stopped = true;
            if (timer) clearTimeout(timer);
          };
        }, 'agent-pet:overlay-commands');
      },
    };
  },
});
