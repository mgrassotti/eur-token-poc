# RGB HTTP sidecar for eur-token-poc (rgb-lib 0.3.x, regtest).
from __future__ import annotations

import base64
import json
import os
import shutil
import time
from datetime import datetime, timezone
from typing import Any, Optional

import httpx
import rgb_lib
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="eur-token-poc RGB sidecar", version="0.1.0")

ELECTRUM_URL = os.environ.get("ELECTRUM_URL", "tcp://electrs:50001")
RGB_PROXY_URL = os.environ.get("RGB_PROXY_URL", "rpc://rgb-proxy:3000/json-rpc")
TRANSPORT_ENDPOINTS = [RGB_PROXY_URL]
DATA_ROOT = os.environ.get("DATA_ROOT", "/data/wallets")
BITCOIND_RPC_URL = os.environ.get("BITCOIND_RPC_URL", "http://regtest:regtest@bitcoind:18443")
FEE_RATE = int(os.environ.get("FEE_RATE", "2"))
BITCOIN_NETWORK = rgb_lib.BitcoinNetwork.REGTEST
SUPPORTED_SCHEMAS = [rgb_lib.AssetSchema.NIA]
VANILLA_SYNC_LOOKBACK = 20
ONLINE_CACHE: dict[str, Any] = {}  # unused; online handles are bound to Wallet instances


class WalletCreateRequest(BaseModel):
    wallet_id: str
    mnemonic: Optional[str] = None


class IssueRequest(BaseModel):
    wallet_id: str
    ticker: str
    name: str
    precision: int = 0
    amounts: list[int]


class ReceiveRequest(BaseModel):
    wallet_id: str
    asset_id: Optional[str] = None
    amount: int


class SendRequest(BaseModel):
    sender_wallet_id: str
    asset_id: str
    recipient_id: str
    amount: int
    recipient_wallet_id: str


def wallet_dir(wallet_id: str) -> str:
    path = os.path.join(DATA_ROOT, wallet_id)
    os.makedirs(path, exist_ok=True)
    return path


def meta_path(wallet_id: str) -> str:
    return os.path.join(wallet_dir(wallet_id), "meta.json")


def load_meta(wallet_id: str) -> dict[str, Any]:
    path = meta_path(wallet_id)
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail=f"wallet {wallet_id} not found")
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def save_meta(wallet_id: str, meta: dict[str, Any]) -> None:
    with open(meta_path(wallet_id), "w", encoding="utf-8") as handle:
        json.dump(meta, handle)


def expiration_timestamp(offset_seconds: int = 3600) -> int:
    return int(datetime.now(timezone.utc).timestamp()) + offset_seconds


def open_wallet(wallet_id: str) -> rgb_lib.Wallet:
    meta = load_meta(wallet_id)
    wallet_data = rgb_lib.WalletData(
        data_dir=wallet_dir(wallet_id),
        bitcoin_network=BITCOIN_NETWORK,
        database_type=rgb_lib.DatabaseType.SQLITE,
        max_allocations_per_utxo=1,
        supported_schemas=SUPPORTED_SCHEMAS,
    )
    singlesig_keys = rgb_lib.SinglesigKeys(
        account_xpub_vanilla=meta["account_xpub_vanilla"],
        account_xpub_colored=meta["account_xpub_colored"],
        vanilla_keychain=None,
        master_fingerprint=meta["master_fingerprint"],
        mnemonic=meta["mnemonic"],
        witness_version=rgb_lib.WitnessVersion.TAPROOT,
    )
    return rgb_lib.Wallet(wallet_data, singlesig_keys)


def go_online(wallet: rgb_lib.Wallet, wallet_id: str):
    return wallet.go_online(
        rgb_lib.OnlineOptions(
            indexer_url=ELECTRUM_URL,
            skip_consistency_check=True,
            vanilla_sync_lookback=VANILLA_SYNC_LOOKBACK,
        )
    )


def bitcoind_rpc(method: str, params: list[Any] | None = None, *, wallet: str | None = None) -> Any:
    base = BITCOIND_RPC_URL.rstrip("/")
    url = f"{base}/wallet/{wallet}" if wallet else base
    payload = {"jsonrpc": "1.0", "id": 1, "method": method, "params": params or []}
    response = httpx.post(url, json=payload, timeout=30.0)
    # bitcoind returns HTTP 500 for JSON-RPC application errors; still parse the body.
    try:
        body = response.json()
    except ValueError as exc:
        response.raise_for_status()
        raise HTTPException(status_code=502, detail="invalid bitcoind response") from exc

    if body.get("error"):
        raise HTTPException(status_code=502, detail=body["error"])
    return body["result"]


FUNDING_WALLET = "l1_external_wallet"


def ensure_btc_funds(address: str, amount_sats: int = 100_000) -> None:
    try:
        bitcoind_rpc("loadwallet", [FUNDING_WALLET])
    except HTTPException:
        pass

    balance_btc = float(bitcoind_rpc("getbalance", [], wallet=FUNDING_WALLET))
    needed_btc = (amount_sats + 50_000) / 100_000_000.0
    if balance_btc < needed_btc:
        raise HTTPException(
            status_code=502,
            detail=f"{FUNDING_WALLET} balance insufficient for RGB funding",
        )

    bitcoind_rpc("sendtoaddress", [address, amount_sats / 100_000_000.0], wallet=FUNDING_WALLET)
    mining_addr = bitcoind_rpc("getnewaddress", [], wallet=FUNDING_WALLET)
    bitcoind_rpc("generatetoaddress", [1, mining_addr])


@app.get("/health")
def health():
    return {"ok": True, "electrum_url": ELECTRUM_URL, "proxy": RGB_PROXY_URL}


@app.post("/wallets/reset-all")
def reset_all_wallets():
    """Wipe persisted wallet data (regtest only — for spec isolation)."""
    removed = []
    if os.path.isdir(DATA_ROOT):
        for name in os.listdir(DATA_ROOT):
            path = os.path.join(DATA_ROOT, name)
            if os.path.isdir(path):
                shutil.rmtree(path)
                removed.append(name)
    os.makedirs(DATA_ROOT, exist_ok=True)
    return {"ok": True, "removed": removed}


@app.post("/wallets")
def create_wallet(body: WalletCreateRequest):
    wallet_id = body.wallet_id
    if os.path.exists(meta_path(wallet_id)):
        return {"wallet_id": wallet_id, "created": False, **load_meta(wallet_id)}

    keys = (
        rgb_lib.restore_keys(BITCOIN_NETWORK, body.mnemonic, rgb_lib.WitnessVersion.TAPROOT)
        if body.mnemonic
        else rgb_lib.generate_keys(BITCOIN_NETWORK, rgb_lib.WitnessVersion.TAPROOT)
    )

    meta = {
        "wallet_id": wallet_id,
        "mnemonic": keys.mnemonic,
        "master_fingerprint": keys.master_fingerprint,
        "account_xpub_vanilla": keys.account_xpub_vanilla,
        "account_xpub_colored": keys.account_xpub_colored,
    }
    save_meta(wallet_id, meta)

    wallet = open_wallet(wallet_id)
    address = wallet.get_address()

    return {"wallet_id": wallet_id, "created": True, "address": address, **meta}


@app.post("/wallets/{wallet_id}/setup")
def setup_wallet(wallet_id: str):
    wallet = open_wallet(wallet_id)
    address = wallet.get_address()
    ensure_btc_funds(address)
    online = go_online(wallet, wallet_id)
    wallet.refresh(online, None, [], False)
    try:
        created = wallet.create_utxos(online, True, 5, None, FEE_RATE, False)
    except rgb_lib.RgbLibError.AllocationsAlreadyAvailable:
        created = 0
    wallet.refresh(online, None, [], False)
    return {"wallet_id": wallet_id, "address": address, "utxos_created": created}


@app.get("/wallets/{wallet_id}/assets")
def list_assets(wallet_id: str):
    wallet = open_wallet(wallet_id)
    online = go_online(wallet, wallet_id)
    wallet.refresh(online, None, [], False)
    assets = wallet.list_assets(filter_asset_schemas=[])
    return {
        "nia": [
            {
                "asset_id": asset.asset_id,
                "ticker": asset.ticker,
                "name": asset.name,
                "balance": {
                    "settled": asset.balance.settled,
                    "future": asset.balance.future,
                    "spendable": asset.balance.spendable,
                },
                "precision": asset.precision,
            }
            for asset in assets.nia
        ]
    }


@app.post("/issue")
def issue_asset(body: IssueRequest):
    wallet = open_wallet(body.wallet_id)
    online = go_online(wallet, body.wallet_id)
    asset = wallet.issue_asset_nia(body.ticker, body.name, body.precision, body.amounts)
    wallet.refresh(online, None, [], False)
    return {
        "asset_id": asset.asset_id,
        "ticker": body.ticker,
        "name": body.name,
        "issued_amounts": body.amounts,
    }


@app.post("/receive/blind")
def blind_receive(body: ReceiveRequest):
    wallet = open_wallet(body.wallet_id)
    go_online(wallet, body.wallet_id)
    asset_id = body.asset_id
    if asset_id:
        known = {a.asset_id for a in wallet.list_assets(filter_asset_schemas=[]).nia}
        asset_id = asset_id if asset_id in known else None
    receive = wallet.blind_receive(
        asset_id,
        rgb_lib.Assignment.FUNGIBLE(body.amount),
        expiration_timestamp(),
        TRANSPORT_ENDPOINTS,
        1,
    )
    return {
        "invoice": receive.invoice,
        "recipient_id": receive.recipient_id,
        "expiration_timestamp": receive.expiration_timestamp,
    }


@app.post("/send")
def send_asset(body: SendRequest):
    sender = open_wallet(body.sender_wallet_id)
    online = go_online(sender, body.sender_wallet_id)

    recipient_map = {
        body.asset_id: [
            rgb_lib.Recipient(
                recipient_id=body.recipient_id,
                witness_data=None,
                assignment=rgb_lib.Assignment.FUNGIBLE(body.amount),
                transport_endpoints=TRANSPORT_ENDPOINTS,
            )
        ]
    }

    txid = sender.send(
        online,
        recipient_map,
        True,
        FEE_RATE,
        1,
        expiration_timestamp(),
    )

    mining_addr = bitcoind_rpc("getnewaddress", [], wallet=FUNDING_WALLET)
    bitcoind_rpc("generatetoaddress", [6, mining_addr])

    recipient = open_wallet(body.recipient_wallet_id)
    recipient_online = go_online(recipient, body.recipient_wallet_id)
    sender.refresh(online, None, [], False)
    refreshed = recipient.refresh(recipient_online, None, [], False)

    return {"txid": txid, "recipient_refresh": refreshed}


@app.get("/wallets/{wallet_id}/consignments/latest")
def latest_consignment(wallet_id: str):
    # rgb-lib stores transfers locally; expose refresh summary for Rails UI.
    wallet = open_wallet(wallet_id)
    online = go_online(wallet, wallet_id)
    refreshed = wallet.refresh(online, None, [], False)
    return {"wallet_id": wallet_id, "refreshed": refreshed}
