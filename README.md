# logos-zebrad-ui

`zebrad_ui` manages the Zcash node (Zebra) that `zebrad_module` runs in-process: start and
stop it, watch it sync, change its settings, choose what it opens to other programs, and read
its log. Built on the Logos Design System, like the Monero node app it is copied from.

```bash
nix build .#install        # -dev variant, for logos-standalone-app
nix build .#lgx
```

- **Status:** the state and last error, height against Zebra's estimate of the network tip with
  a progress bar, finalized height, peers, uptime, version and the cache directory. A node
  with fewer than three peers reads **Waiting for peers**: in testing, 4 of 18 starts held
  only 2 peers for 45 s to 5 min and synced at a crawl meanwhile. A node at the tip
  with no peer left reads **No peers**, not Synced.
- **Disk:** a mainnet node keeps the whole chain, about 300 GB, in its cache directory; the
  view says so before a mainnet start.
- **Settings**, per network, applied on the next start and locked while the node runs:
  cache directory, listen address, initial peers, log filter, and on regtest the miner address.
- **Open to other programs:** `exposeLightwalletd` and `exposeJsonRpc` are off by default.
  Turning one on goes through a warning first: the port has no TLS (and lightwalletd no
  authentication), and any program on this computer, or a web page in a browser on it, can
  reach it. The status card shows every port that is open. The wallet never needs them: it
  reaches the node over Logos IPC.

The view polls `status()` and the log tail every 2 s, and applies `zebradStateChanged` as it
arrives: the event marks state changes, while height and peers move between them.

## Intents

The app **provides** `zcash.node.configure` (handoff). A request may carry
`{"network": "mainnet"}`; if the node is stopped the view switches to that network. The
Zcash wallet's "Manage local node…" sends it.
