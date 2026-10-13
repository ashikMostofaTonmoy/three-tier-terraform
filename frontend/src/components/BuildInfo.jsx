import { useEffect, useState } from 'react';

// __BUILD_ID__ is replaced with a real string when the app is built
// (see frontend/vite.config.js). Showing it on screen means you can look at
// the running site and know exactly which build is live right now.
const BUILD_ID = __BUILD_ID__;

// Which backend answered: its version and, in the blue/green lesson, its
// color. Polled every few seconds so a traffic switch shows up on screen
// without reloading. Lessons whose backend has no /health simply hide it.
function useBackendInfo() {
  const [info, setInfo] = useState(null);
  useEffect(() => {
    let alive = true;
    const load = () =>
      fetch('/health', { cache: 'no-store' })
        .then((r) => (r.ok ? r.json() : null))
        .then((d) => alive && setInfo(d && d.version ? d : null))
        .catch(() => alive && setInfo(null));
    load();
    const id = setInterval(load, 3000);
    return () => {
      alive = false;
      clearInterval(id);
    };
  }, []);
  return info;
}

export default function BuildInfo() {
  const backend = useBackendInfo();
  return (
    <footer className="build-info">
      build <code>{BUILD_ID}</code>
      {backend && (
        <>
          {' · API '}
          {backend.color && (
            <span className={`color-badge color-${backend.color}`}>{backend.color}</span>
          )}
          <code>{backend.version}</code>
        </>
      )}
    </footer>
  );
}
