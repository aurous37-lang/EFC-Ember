# Deployment Records

Use this directory for public, non-secret deployment records by chain.

Recommended filename:

```text
<chain-id>.json
```

Recommended fields:

```json
{
  "chainId": 1,
  "network": "mainnet",
  "maintenancePoolFactory": "0x...",
  "emberFactory": "0x...",
  "standardAuthor": "0x...",
  "recoveryTreasury": "0x...",
  "factoryOwner": "0x...",
  "canonicalUsdc": "0x...",
  "seededLicenses": ["MIT"],
  "transactions": {
    "maintenancePoolFactory": "0x...",
    "emberFactory": "0x..."
  }
}
```

Do not store private keys, RPC credentials, or unpublished deployment plans here.
