import React, { useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import {
  CheckCircle2,
  Database,
  ExternalLink,
  FileCheck2,
  KeyRound,
  Link2,
  Loader2,
  Play,
  ShieldCheck,
  Wallet,
} from 'lucide-react';
import {
  type Address,
  type Hash,
  type Hex,
  createPublicClient,
  createWalletClient,
  custom,
  formatUnits,
  getAddress,
  isAddress,
  keccak256,
  stringToHex,
} from 'viem';

import { contracts } from './generated/contracts';
import './styles.css';

type LogEntry = { kind: 'ok' | 'info' | 'error'; text: string };

type FactoryState = {
  maintenancePoolFactory: Address | '';
  emberFactory: Address | '';
  standardAuthor: Address | '';
  recoveryTreasury: Address | '';
  owner: Address | '';
  pendingOwner: Address | '';
};

type ProjectState = {
  ember: Address | '';
  pool: Address | '';
  developer: Address | '';
  dapp: Address | '';
  usdc: Address | '';
  canonicalUsdc: Address | '';
  name: string;
  symbol: string;
  initialSupply: string;
  originalCommitment: Hex | '';
  originalEncryptedCID: string;
  archiveHash: Hex | '';
  fileTreeMerkleRoot: Hex | '';
  lockfileHash: Hex | '';
  buildArtifactHash: Hex | '';
  spdxLicense: string;
  manifestCID: string;
  basePrice: string;
  slope: string;
  spawnPool: boolean;
  poolMode: string;
  poolGovernor: Address | '';
  poolTimelockDelay: string;
  parentDeployment: Hex;
};

const zeroBytes32 = `0x${'0'.repeat(64)}` as Hex;
const zeroAddress = '0x0000000000000000000000000000000000000000' as Address;

function requireAddress(value: string, label: string): Address {
  if (!isAddress(value)) throw new Error(`${label} is not an address`);
  return getAddress(value);
}

function requireHex32(value: string, label: string): Hex {
  if (!/^0x[0-9a-fA-F]{64}$/.test(value)) throw new Error(`${label} must be bytes32`);
  if (value === zeroBytes32) throw new Error(`${label} is zero`);
  return value as Hex;
}

function optionalHex32(value: string, label: string): Hex {
  if (!/^0x[0-9a-fA-F]{64}$/.test(value)) throw new Error(`${label} must be bytes32`);
  return value as Hex;
}

function requirePositiveInt(value: string, label: string): bigint {
  if (!/^\d+$/.test(value)) throw new Error(`${label} must be an integer`);
  const parsed = BigInt(value);
  if (parsed === 0n) throw new Error(`${label} is zero`);
  return parsed;
}

function requireUint(value: string, label: string): bigint {
  if (!/^\d+$/.test(value)) throw new Error(`${label} must be an integer`);
  return BigInt(value);
}

function licenseHash(spdx: string): Hex {
  return keccak256(stringToHex(spdx));
}

function txLink(hash: Hash) {
  return hash;
}

function App() {
  const [account, setAccount] = useState<Address | ''>('');
  const [chainId, setChainId] = useState<bigint | null>(null);
  const [expectedChainId, setExpectedChainId] = useState('8453');
  const [factory, setFactory] = useState<FactoryState>({
    maintenancePoolFactory: '',
    emberFactory: '',
    standardAuthor: '',
    recoveryTreasury: '',
    owner: '',
    pendingOwner: zeroAddress,
  });
  const [project, setProject] = useState<ProjectState>({
    ember: '',
    pool: zeroAddress,
    developer: '',
    dapp: '',
    usdc: '',
    canonicalUsdc: '',
    name: 'Example Ember',
    symbol: 'EMBER',
    initialSupply: '1000000',
    originalCommitment: '',
    originalEncryptedCID: 'ipfs://encrypted-source-cid',
    archiveHash: '',
    fileTreeMerkleRoot: '',
    lockfileHash: '',
    buildArtifactHash: '',
    spdxLicense: 'MIT',
    manifestCID: 'ipfs://source-manifest-cid',
    basePrice: '10000',
    slope: '0',
    spawnPool: true,
    poolMode: '1',
    poolGovernor: '',
    poolTimelockDelay: '604800',
    parentDeployment: zeroBytes32,
  });
  const [license, setLicense] = useState('MIT');
  const [newOwner, setNewOwner] = useState<Address | ''>('');
  const [registry, setRegistry] = useState<Array<{ token: Address; developer: Address; pool: Address }>>([]);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [busy, setBusy] = useState(false);

  const provider = window.ethereum;
  const clients = useMemo(() => {
    if (!provider) return null;
    return {
      publicClient: createPublicClient({ transport: custom(provider) }),
      walletClient: createWalletClient({ transport: custom(provider) }),
    };
  }, [provider]);

  function log(kind: LogEntry['kind'], text: string) {
    setLogs((current) => [{ kind, text }, ...current].slice(0, 12));
  }

  async function run(label: string, task: () => Promise<void>) {
    if (!clients) {
      log('error', 'Wallet provider not found');
      return;
    }
    setBusy(true);
    try {
      await task();
      log('ok', label);
    } catch (error) {
      log('error', error instanceof Error ? error.message : String(error));
    } finally {
      setBusy(false);
    }
  }

  async function connect() {
    await run('Wallet connected', async () => {
      if (!clients) return;
      const [addr] = await clients.walletClient.requestAddresses();
      const id = await clients.publicClient.getChainId();
      setAccount(addr);
      setChainId(BigInt(id));
      setFactory((current) => ({ ...current, owner: addr }));
      setProject((current) => ({ ...current, developer: addr }));
    });
  }

  function assertChain() {
    if (chainId === null) throw new Error('Connect wallet first');
    if (chainId !== BigInt(expectedChainId)) throw new Error('Connected chain does not match expected chain');
  }

  async function deployFactory() {
    await run('Factory deployed', async () => {
      if (!clients || !account) throw new Error('Connect wallet first');
      assertChain();
      const standardAuthor = requireAddress(factory.standardAuthor, 'Standard author');
      const recoveryTreasury = requireAddress(factory.recoveryTreasury, 'Recovery treasury');
      if (standardAuthor === recoveryTreasury) throw new Error('Recipients must differ');

      const poolHash = await clients.walletClient.deployContract({
        account,
        chain: null,
        abi: contracts.MaintenancePoolFactory.abi,
        bytecode: contracts.MaintenancePoolFactory.bytecode,
      });
      log('info', `MaintenancePoolFactory tx ${txLink(poolHash)}`);
      const poolReceipt = await clients.publicClient.waitForTransactionReceipt({ hash: poolHash });
      if (!poolReceipt.contractAddress) throw new Error('Pool factory address missing');
      const deployedPoolFactory = poolReceipt.contractAddress;

      const emberHash = await clients.walletClient.deployContract({
        account,
        chain: null,
        abi: contracts.EmberFactory.abi,
        bytecode: contracts.EmberFactory.bytecode,
        args: [standardAuthor, recoveryTreasury, deployedPoolFactory],
      });
      log('info', `EmberFactory tx ${txLink(emberHash)}`);
      const emberReceipt = await clients.publicClient.waitForTransactionReceipt({ hash: emberHash });
      if (!emberReceipt.contractAddress) throw new Error('EmberFactory address missing');
      const deployedEmberFactory = emberReceipt.contractAddress;

      setFactory((current) => ({
        ...current,
        maintenancePoolFactory: deployedPoolFactory,
        emberFactory: deployedEmberFactory,
        owner: account,
        pendingOwner: zeroAddress,
      }));
    });
  }

  async function checkFactory() {
    await run('Factory wiring checked', async () => {
      if (!clients) throw new Error('Connect wallet first');
      assertChain();
      const emberFactory = requireAddress(factory.emberFactory, 'EmberFactory');
      const [standardAuthor, recoveryTreasury, poolFactory, owner, pendingOwner] = await Promise.all([
        clients.publicClient.readContract({ address: emberFactory, abi: contracts.EmberFactory.abi, functionName: 'STANDARD_AUTHOR' }),
        clients.publicClient.readContract({ address: emberFactory, abi: contracts.EmberFactory.abi, functionName: 'RECOVERY_TREASURY' }),
        clients.publicClient.readContract({ address: emberFactory, abi: contracts.EmberFactory.abi, functionName: 'POOL_FACTORY' }),
        clients.publicClient.readContract({ address: emberFactory, abi: contracts.EmberFactory.abi, functionName: 'owner' }),
        clients.publicClient.readContract({ address: emberFactory, abi: contracts.EmberFactory.abi, functionName: 'pendingOwner' }),
      ]);
      setFactory((current) => ({
        ...current,
        standardAuthor: standardAuthor as Address,
        recoveryTreasury: recoveryTreasury as Address,
        maintenancePoolFactory: poolFactory as Address,
        owner: owner as Address,
        pendingOwner: pendingOwner as Address,
      }));
    });
  }

  async function seedLicense() {
    await run('License seeded', async () => {
      if (!clients || !account) throw new Error('Connect wallet first');
      assertChain();
      const emberFactory = requireAddress(factory.emberFactory, 'EmberFactory');
      if (!license.trim()) throw new Error('License is empty');
      const hash = await clients.walletClient.writeContract({
        account,
        chain: null,
        address: emberFactory,
        abi: contracts.EmberFactory.abi,
        functionName: 'setLicenseApproval',
        args: [license.trim(), true],
      });
      await clients.publicClient.waitForTransactionReceipt({ hash });
      setProject((current) => ({ ...current, spdxLicense: license.trim() }));
    });
  }

  async function checkLicense() {
    await run('License approval checked', async () => {
      if (!clients) throw new Error('Connect wallet first');
      assertChain();
      const emberFactory = requireAddress(factory.emberFactory, 'EmberFactory');
      const approved = await clients.publicClient.readContract({
        address: emberFactory,
        abi: contracts.EmberFactory.abi,
        functionName: 'approvedLicense',
        args: [licenseHash(license.trim())],
      });
      if (!approved) throw new Error('License is not approved');
    });
  }

  async function checkUsdc() {
    await run('Canonical USDC checked', async () => {
      if (!clients) throw new Error('Connect wallet first');
      assertChain();
      const usdc = requireAddress(project.usdc, 'USDC');
      const canonical = requireAddress(project.canonicalUsdc, 'Canonical USDC');
      if (usdc !== canonical) throw new Error('USDC is not canonical');
      const decimals = await clients.publicClient.readContract({
        address: usdc,
        abi: contracts.IERC20Token.abi,
        functionName: 'decimals',
      });
      if (decimals !== 6) throw new Error('USDC decimals mismatch');
    });
  }

  async function transferOwnership() {
    await run('Ownership transfer started', async () => {
      if (!clients || !account) throw new Error('Connect wallet first');
      assertChain();
      const emberFactory = requireAddress(factory.emberFactory, 'EmberFactory');
      const owner = requireAddress(newOwner, 'New owner');
      const hash = await clients.walletClient.writeContract({
        account,
        chain: null,
        address: emberFactory,
        abi: contracts.EmberFactory.abi,
        functionName: 'transferOwnership',
        args: [owner],
      });
      await clients.publicClient.waitForTransactionReceipt({ hash });
      setFactory((current) => ({ ...current, pendingOwner: owner }));
    });
  }

  async function deployProject() {
    await run('Project deployed', async () => {
      if (!clients || !account) throw new Error('Connect wallet first');
      assertChain();
      if (requireAddress(project.developer, 'Project developer') !== account) {
        throw new Error('Connected wallet must be the project developer');
      }
      const emberFactory = requireAddress(factory.emberFactory, 'EmberFactory');
      const usdc = requireAddress(project.usdc, 'USDC');
      const canonical = requireAddress(project.canonicalUsdc, 'Canonical USDC');
      if (usdc !== canonical) throw new Error('USDC is not canonical');
      if (!project.name.trim() || !project.symbol.trim()) throw new Error('Name and symbol are required');
      const initialSupply = requirePositiveInt(project.initialSupply, 'Initial supply');
      const basePrice = requireUint(project.basePrice, 'Base price');
      const slope = requireUint(project.slope, 'Slope');
      if (basePrice === 0n && slope === 0n) throw new Error('No price');
      const poolMode = Number(project.poolMode);
      if (!Number.isInteger(poolMode) || poolMode < 0 || poolMode > 4) throw new Error('Pool mode out of range');
      const poolDelay = requireUint(project.poolTimelockDelay, 'Pool timelock delay');
      if (project.spawnPool && (poolDelay < 86_400n || poolDelay > 2_592_000n)) throw new Error('Pool delay out of range');
      if (!project.spawnPool && project.poolGovernor && project.poolGovernor !== zeroAddress) throw new Error('Pool governor unused');

      const approved = await clients.publicClient.readContract({
        address: emberFactory,
        abi: contracts.EmberFactory.abi,
        functionName: 'approvedLicense',
        args: [licenseHash(project.spdxLicense)],
      });
      if (!approved) throw new Error('License is not approved');

      const manifest = {
        archiveHash: requireHex32(project.archiveHash, 'Archive hash'),
        fileTreeMerkleRoot: requireHex32(project.fileTreeMerkleRoot, 'File tree root'),
        lockfileHash: requireHex32(project.lockfileHash, 'Lockfile hash'),
        buildArtifactHash: requireHex32(project.buildArtifactHash, 'Build artifact hash'),
        spdxLicense: project.spdxLicense,
        manifestCID: project.manifestCID,
      };

      const hash = await clients.walletClient.writeContract({
        account,
        chain: null,
        address: emberFactory,
        abi: contracts.EmberFactory.abi,
        functionName: 'deploy',
        args: [
          project.name,
          project.symbol,
          initialSupply,
          requireAddress(project.dapp, 'dApp'),
          requireHex32(project.originalCommitment, 'Original commitment'),
          project.originalEncryptedCID,
          manifest,
          usdc,
          basePrice,
          slope,
          project.spawnPool,
          poolMode,
          project.spawnPool ? requireAddress(project.poolGovernor, 'Pool governor') : zeroAddress,
          poolDelay,
          optionalHex32(project.parentDeployment, 'Parent deployment'),
        ],
      });
      log('info', `Deploy project tx ${txLink(hash)}`);
      await clients.publicClient.waitForTransactionReceipt({ hash });
    });
  }

  async function loadRegistry() {
    await run('Registry loaded', async () => {
      if (!clients) throw new Error('Connect wallet first');
      assertChain();
      const emberFactory = requireAddress(factory.emberFactory, 'EmberFactory');
      const count = await clients.publicClient.readContract({
        address: emberFactory,
        abi: contracts.EmberFactory.abi,
        functionName: 'deploymentCount',
      });
      const items = [];
      for (let i = 0n; i < (count as bigint); i += 1n) {
        const token = (await clients.publicClient.readContract({
          address: emberFactory,
          abi: contracts.EmberFactory.abi,
          functionName: 'deployments',
          args: [i],
        })) as Address;
        const info = (await clients.publicClient.readContract({
          address: emberFactory,
          abi: contracts.EmberFactory.abi,
          functionName: 'info',
          args: [token],
        })) as readonly [Address, bigint, Address, Hex, boolean];
        items.push({ token, developer: info[0], pool: info[2] });
      }
      setRegistry(items);
    });
  }

  const chainStatus = chainId === null ? 'disconnected' : chainId === BigInt(expectedChainId) ? 'matched' : 'mismatch';

  return (
    <main>
      <header className="topbar">
        <div>
          <h1>ERC-EMBER Deployer</h1>
          <p>Reference launch console</p>
        </div>
        <button onClick={connect} disabled={busy}>
          <Wallet size={18} />
          {account ? short(account) : 'Connect'}
        </button>
      </header>

      <section className="statusline">
        <label>
          Chain
          <input value={expectedChainId} onChange={(event) => setExpectedChainId(event.target.value)} />
        </label>
        <span className={`pill ${chainStatus}`}>{chainStatus}</span>
        {busy && (
          <span className="spin">
            <Loader2 size={16} /> pending
          </span>
        )}
      </section>

      <div className="layout">
        <section className="panel">
          <h2>Factory</h2>
          <Grid>
            <Text label="Standard author" value={factory.standardAuthor} onChange={(value) => setFactory({ ...factory, standardAuthor: value as Address })} />
            <Text label="Recovery treasury" value={factory.recoveryTreasury} onChange={(value) => setFactory({ ...factory, recoveryTreasury: value as Address })} />
            <Text label="Pool factory" value={factory.maintenancePoolFactory} onChange={(value) => setFactory({ ...factory, maintenancePoolFactory: value as Address })} />
            <Text label="Ember factory" value={factory.emberFactory} onChange={(value) => setFactory({ ...factory, emberFactory: value as Address })} />
            <Text label="Owner" value={factory.owner} onChange={(value) => setFactory({ ...factory, owner: value as Address })} />
            <Text label="Pending owner" value={factory.pendingOwner} onChange={(value) => setFactory({ ...factory, pendingOwner: value as Address })} />
          </Grid>
          <Actions>
            <button onClick={deployFactory} disabled={busy}><Play size={16} /> Deploy</button>
            <button onClick={checkFactory} disabled={busy}><ShieldCheck size={16} /> Check</button>
          </Actions>
        </section>

        <section className="panel">
          <h2>Policy</h2>
          <Grid>
            <Text label="SPDX" value={license} onChange={setLicense} />
            <Text label="USDC" value={project.usdc} onChange={(value) => setProject({ ...project, usdc: value as Address })} />
            <Text label="Canonical USDC" value={project.canonicalUsdc} onChange={(value) => setProject({ ...project, canonicalUsdc: value as Address })} />
            <Text label="New owner" value={newOwner} onChange={(value) => setNewOwner(value as Address)} />
          </Grid>
          <Actions>
            <button onClick={seedLicense} disabled={busy}><FileCheck2 size={16} /> Seed</button>
            <button onClick={checkLicense} disabled={busy}><CheckCircle2 size={16} /> License</button>
            <button onClick={checkUsdc} disabled={busy}><Database size={16} /> USDC</button>
            <button onClick={transferOwnership} disabled={busy}><KeyRound size={16} /> Owner</button>
          </Actions>
        </section>

        <section className="panel wide">
          <h2>Project</h2>
          <Grid>
            <Text label="Name" value={project.name} onChange={(value) => setProject({ ...project, name: value })} />
            <Text label="Symbol" value={project.symbol} onChange={(value) => setProject({ ...project, symbol: value })} />
            <Text label="Supply" value={project.initialSupply} onChange={(value) => setProject({ ...project, initialSupply: value })} />
            <Text label="Developer" value={project.developer} onChange={(value) => setProject({ ...project, developer: value as Address })} />
            <Text label="dApp" value={project.dapp} onChange={(value) => setProject({ ...project, dapp: value as Address })} />
            <Text label="Commitment" value={project.originalCommitment} onChange={(value) => setProject({ ...project, originalCommitment: value as Hex })} />
            <Text label="Encrypted CID" value={project.originalEncryptedCID} onChange={(value) => setProject({ ...project, originalEncryptedCID: value })} />
            <Text label="Archive hash" value={project.archiveHash} onChange={(value) => setProject({ ...project, archiveHash: value as Hex })} />
            <Text label="Tree root" value={project.fileTreeMerkleRoot} onChange={(value) => setProject({ ...project, fileTreeMerkleRoot: value as Hex })} />
            <Text label="Lockfile hash" value={project.lockfileHash} onChange={(value) => setProject({ ...project, lockfileHash: value as Hex })} />
            <Text label="Artifact hash" value={project.buildArtifactHash} onChange={(value) => setProject({ ...project, buildArtifactHash: value as Hex })} />
            <Text label="Manifest CID" value={project.manifestCID} onChange={(value) => setProject({ ...project, manifestCID: value })} />
            <Text label="Base price" value={project.basePrice} onChange={(value) => setProject({ ...project, basePrice: value })} />
            <Text label="Slope" value={project.slope} onChange={(value) => setProject({ ...project, slope: value })} />
            <Text label="Pool mode" value={project.poolMode} onChange={(value) => setProject({ ...project, poolMode: value })} />
            <Text label="Pool governor" value={project.poolGovernor} onChange={(value) => setProject({ ...project, poolGovernor: value as Address })} />
            <Text label="Pool delay" value={project.poolTimelockDelay} onChange={(value) => setProject({ ...project, poolTimelockDelay: value })} />
            <Text label="Parent" value={project.parentDeployment} onChange={(value) => setProject({ ...project, parentDeployment: value as Hex })} />
          </Grid>
          <label className="toggle">
            <input type="checkbox" checked={project.spawnPool} onChange={(event) => setProject({ ...project, spawnPool: event.target.checked })} />
            Maintenance pool
          </label>
          <Actions>
            <button onClick={deployProject} disabled={busy}><Play size={16} /> Deploy project</button>
          </Actions>
        </section>

        <section className="panel">
          <h2>Registry</h2>
          <Actions>
            <button onClick={loadRegistry} disabled={busy}><Link2 size={16} /> Load</button>
          </Actions>
          <div className="table">
            {registry.map((item) => (
              <div className="row" key={item.token}>
                <span>{short(item.token)}</span>
                <span>{short(item.developer)}</span>
                <span>{item.pool === zeroAddress ? 'no pool' : short(item.pool)}</span>
              </div>
            ))}
          </div>
        </section>

        <section className="panel">
          <h2>Log</h2>
          <div className="log">
            {logs.map((entry, index) => (
              <div className={entry.kind} key={`${entry.text}-${index}`}>
                {entry.kind === 'ok' ? <CheckCircle2 size={15} /> : <ExternalLink size={15} />}
                <span>{entry.text}</span>
              </div>
            ))}
          </div>
        </section>
      </div>
    </main>
  );
}

function short(value: string) {
  return value ? `${value.slice(0, 6)}...${value.slice(-4)}` : '';
}

function Grid({ children }: { children: React.ReactNode }) {
  return <div className="grid">{children}</div>;
}

function Actions({ children }: { children: React.ReactNode }) {
  return <div className="actions">{children}</div>;
}

function Text({ label, value, onChange }: { label: string; value: string; onChange: (value: string) => void }) {
  return (
    <label>
      {label}
      <input value={value} onChange={(event) => onChange(event.target.value)} spellCheck={false} />
    </label>
  );
}

createRoot(document.getElementById('root')!).render(<App />);
