# polku-oracle-retry

Gets a free Oracle Cloud server for Polku's own BRouter (and later Overpass),
so Polku does not depend on the per-IP limits of the public services.

This README is the single place for the plan and the current state.
Update it when something changes.

## Current state (31 Oct 2026)

- **No server yet.** Every attempt so far has failed with Oracle's
  "Out of host capacity" (no free Ampere machines in Stockholm).
- The workflow in this repo keeps retrying. When a server is created,
  it opens an issue titled "Polku BRouter server created" with the address.

## What exists in Oracle

| Thing | Value |
|---|---|
| Account (tenancy) | `tommicontursi`, home region `eu-stockholm-1` |
| Network | VCN `polku-vcn`, subnet `public subnet-polku-vcn` |
| Open ports | TCP 22, 80, 443 (default security list of `polku-vcn`) |
| Resource Manager stack | `polku-brouter`, OCID `ocid1.ormstack.oc1.eu-stockholm-1.amaaaaaa77nokliaa6sixcsvscqg3iunqanhjxdngycopqfdt2hxewsqsxaq` |

Always Free resources can only be created in the home region (Stockholm).

## What the stack creates

Source is in [`stack/`](stack/) (`main.tf`, `cloud-init.sh`). This is the same
code that was uploaded to the Oracle stack. If you change it here, upload it to
the stack again (Stack → Edit → upload the files).

- One `VM.Standard.A1.Flex` machine, Ubuntu 24.04 (Arm), public IP.
- Size comes from the stack variables `ocpus` and `memory_gbs`
  (default in `main.tf`: 1 OCPU / 6 GB). The stack is set to 2 OCPU / 12 GB:
  the apply job of 31 Oct 2026 asked for that. Check the current values in
  Oracle: Stack → Variables.
- `cloud-init.sh` runs once on first boot and installs:
  - BRouter 1.7.10 with the Finland data (8 tiles from brouter.de) and Polku's
    profiles, listening only on `127.0.0.1:17777`
  - Caddy in front of it with HTTPS on a free name `<ip-with-dashes>.sslip.io`
  - a weekly data update (Sundays around 04:00 UTC)
  - setup log on the server: `/var/log/polku-setup.log`
- Stack outputs: `public_ip`, `brouter_url`, `ssh_private_key` (hidden, for SSH).

## The retry workflow

`.github/workflows/create-server.yml` starts an apply job on the stack every
5 minutes until a machine called `polku-brouter` exists. After that it only
checks and exits; disable it then.

Repository secrets it needs: `OCI_USER_OCID`, `OCI_FINGERPRINT`,
`OCI_TENANCY_OCID`, `OCI_PRIVATE_KEY` (the private .pem of an Oracle API key).

GitHub's own schedule is unreliable (runs are often hours late or skipped),
which is why the workflow loops inside the job instead of relying on cron alone.
One run keeps trying for up to 5.5 hours (the job limit is 350 minutes). The
cron entry (`*/5 * * * *`) only starts the next run. Runs go one at a time, so
the next run waits until the current one ends.

`TooManyRequests` (429) in the log means Oracle refused to start one apply job.
The OCI CLI retries for about 90 seconds, then the loop tries again 5 minutes
later. Nothing shows that the 5-minute loop causes it, but the cause is not
confirmed.

## Decisions

1. **Free quota is 2 OCPU / 12 GB in total.** Oracle cut it from 4 / 24 in
   June 2026. Older guides still say 4 / 24. The stack must stay within 2 / 12.
2. **BRouter first, Overpass later.** Overpass goes on the same machine, but it
   is installed after the server exists, not in the stack's first-boot script.
   Getting the machine is the hard part; keep each attempt simple.
3. **Polku keeps brouter.de and Valhalla as fallback.** If the own server is down,
   Polku must keep working as it does today.
4. **Pay As You Go is the reliable fix for capacity.** Reports say the machine is
   usually available within hours after the upgrade. Not done yet. If done, add a
   budget alert of 1 EUR (Billing → Budgets). It only sends an email; it does not
   stop charges. The upgrade may put a temporary hold on the card.

## Not verified yet

- `cloud-init.sh` has not run on a real machine.
- BRouter's real memory and speed on A1.
- Overpass disk and memory needs for Finland.

## Next steps

1. Get the server (keep retrying, or upgrade to Pay As You Go).
2. About 10 minutes after creation, test BRouter:
   `https://<host>/brouter?lonlats=24.94,60.17|24.96,60.19&profile=trekking&alternativeidx=0&format=geojson`
   If it fails, read `/var/log/polku-setup.log` on the server.
3. Try it in Polku first via Settings → Routing server. Then make it the default
   (`BROUTER` in `js/config.js`). Polku's PRODUCT.md asks for an issue with gains
   and costs before adding an own service.
4. The stack already asks for 2 OCPU / 12 GB, the whole free quota. Do not raise it.
5. Overpass (phase 2): decide the area (Finland by default), install it on the
   same machine, and add simple monitoring so stale data is noticed.
6. Disable this workflow once the server exists.

## Security notes

- The first Oracle API key was shared in a chat. Make sure it is deleted in
  Oracle (Profile → API keys) and only the newer key is in the secrets.
- Secrets are not visible in logs or to visitors, even in a public repo.
  Logs do show the stack OCID and, later, the server address.
