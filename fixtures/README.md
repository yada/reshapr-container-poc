# Fixtures

`open-meteo-forecast.yml` is a verbatim copy of the Open-Meteo Weather Forecast OpenAPI spec, kept here so `scripts/verify.sh` does not need to download it (`raw.githubusercontent.com` is blocked on some networks).

- Source: https://github.com/open-meteo/open-meteo/blob/main/openapi/forecast.yml
- Fetched with `gh api` from `main` at `b485547236a73d528b721f448d5d19a1b6bd15c5` (2026-11-13); the file's last upstream change is commit `ecd65b64d966224046aaebbcda33a216f0ebd731`.
- Copyright Open-Meteo, spec licence CC BY 4.0 (declared in the file); the upstream repository is AGPL-3.0. It is not modified.

Refresh it with:

```bash
gh api repos/open-meteo/open-meteo/contents/openapi/forecast.yml -H "Accept: application/vnd.github.raw" > fixtures/open-meteo-forecast.yml
```
