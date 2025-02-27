# **Core Testnet Node Setup Guide (Ubuntu/Linux)**

This guide will help you set up a Core Testnet node using an Ubuntu/Linux operating system. It includes all the necessary steps, from installing dependencies to launching the node.

## **Prerequisites**

Before you begin, ensure your system meets the following requirements:

- **Ubuntu 22.04 LTS or later** (with terminal access).
- Basic understanding of **Linux terminal commands**.
- Ensure your system meets the **hardware and system requirements**. [Check eligibility here](https://docs.coredao.org/docs/Node/config/validator-node-config).

## **System Requirements**

- **Storage**: 1 TB SSD (Solid State Drive), gp3, 8k IOPS, 250MB/s throughput, read latency <1ms.
- **CPU**: 4 CPU cores.
- **RAM**: 8 GB.
- **Internet Speed**: Broadband connection with upload/download speeds of at least 10 Mbps.

## **Step-by-Step Guide**

### **Step 1: Update Your System**

Start by ensuring your system is up-to-date.

1. Open a terminal.
2. Run the following commands to update your package list and upgrade installed packages:

   ```bash
   sudo apt update
   sudo apt upgrade -y
   ```

### **Step 2: Install Required Dependencies**

Install the necessary dependencies to build the Core node software.

1. Run the following command to install Git, GCC, Go, and other required tools:

   ```bash
   sudo apt install -y git gcc make curl lz4 golang unzip
   ```

2. Verify the installation of `gcc` and `go`:

   ```bash
   gcc --version
   go version
   ```

You should see version details for both GCC and Go.

### **Step 3: Clone the Core Repository**

1. Clone the `core-chain` repository from GitHub:

   ```bash
   git clone https://github.com/coredao-org/core-chain
   ```

2. Navigate into the cloned directory:

   ```bash
   cd core-chain
   ```

### **Step 4: Install Dependencies for Building Core**

1. Run the following command to install the dependencies for building the `geth` binary:

   ```bash
   make geth
   ```

2. The build process will output details similar to:

   ```bash
   >>> /usr/lib/go-1.22/bin/go build -ldflags "-X github.com/ethereum/go-ethereum/internal/version.gitCommit=afb8bd3ffe652e90a59af26db119bd988a03dd8f ..." -o /home/harystyles/core-chain/build/bin/geth ./cmd/geth
   Done building.
   ```

### **Step 5: Download and Extract the Blockchain Snapshot**

Syncing from the genesis block can be time-consuming. It is recommended to use a snapshot of the blockchain for faster syncing.

1. Download the latest Testnet snapshot from [Core Snapshots GitHub](https://github.com/coredao-org/core-snapshots):

   ```bash
   wget https://snap.coredao.org/coredao-snapshot-testnet-20240327-pruned.tar.lz4
   ```

2. Create a directory for your node data:

   ```bash
   mkdir -p ./node
   ```

3. Decompress and extract the snapshot into the `./node` directory:

   ```bash
   lz4 -d coredao-snapshot-testnet-20240327-pruned.tar.lz4 coredao-snapshot-testnet-20240327-pruned.tar
   tar -xvf coredao-snapshot-testnet-20240327-pruned.tar -C ./node
   ```

### **Step 6: Initialize the Genesis Block**

The `genesis.json` file sets the initial state of the blockchain for your node.

1. Download and extract the `testnet2.zip` release from GitHub:

   ```bash
   wget https://github.com/coredao-org/core-chain/releases/download/v1.0.14/testnet2.zip
   unzip testnet2.zip
   ```

2. Initialize the genesis block with the following command:

   ```bash
   ./build/bin/geth --datadir ./node init ./testnet2/genesis.json
   ```

Ensure that the path to `genesis.json` is correct (`./testnet2/genesis.json`).

### **Step 7: Start Your Node**

You can start the node in two ways:

#### **Option 1: Start the Full Node with Options**

Run the following command to start your node:

```bash
./build/bin/geth --datadir ./node --cache 8000 --rpc.allow-unprotected-txs --networkid 1114
```

This command sets:

- `--datadir ./node`: Location of blockchain data.
- `--cache 8000`: Allocates 8 GB of RAM for performance.
- `--rpc.allow-unprotected-txs`: Allows unprotected transactions (needed for validator actions).
- `--networkid 1114`: Specifies the Testnet network ID.

#### **Option 2: Start the Node with the Configuration File**

Alternatively, you can use a configuration file to help your node connect to peers:

```bash
./build/bin/geth --config ./testnet2/config.toml --datadir ./node --cache 8000 --rpc.allow-unprotected-txs --networkid 1114
```

### **Step 8: Monitor Logs and Performance**

Once your node is running, you can monitor the logs to ensure everything is working properly.

1. To view the logs in real-time, use the following command:

   ```bash
   tail -f ./node/logs/core.log
   ```

---

## **Additional Resources**

- [Core Testnet GitHub Repository](https://github.com/coredao-org/core-chain)
- [Core Snapshots GitHub Repository](https://github.com/coredao-org/core-snapshots)
