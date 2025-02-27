**Running a Core Testnet Node on Ubuntu/Linux**

This guide will walk you through setting up a Core node using an Ubuntu/Linux operating system from scratch. It includes instructions for installing dependencies, building the Core node software, and launching the node.

---

### **Prerequisites**

- **Ubuntu 22.04 LTS or later** (make sure you have terminal access).
- Basic understanding of **Linux terminal commands**.
- Ensure your system meets the **hardware and system requirements**. You can check eligibility [here](#).

---

### **Step 1: Update Your System**

Start by updating your system to ensure all packages are up-to-date.

Open a terminal and run the following commands:

```bash
sudo apt update
sudo apt upgrade -y
```

---

### **Step 2: Install Required Dependencies**

To build Core, you will need Git, GCC, Go, and other tools. Install them with the following command:

```bash
sudo apt install -y git gcc make curl lz4 golang unzip
```

Verify the installations:

```bash
gcc --version
go version
```

You should see version information for both GCC and Go, like:

```bash
gcc (Ubuntu 13.3.0-6ubuntu2~24.04) 13.3.0
go version go1.22.2 linux/amd64
```

---

### **Step 3: Clone the Core Repository**

Now that your system is ready, clone the Core repository from GitHub:

```bash
git clone https://github.com/coredao-org/core-chain
```

Change into the cloned directory:

```bash
cd core-chain
```

---

### **Step 4: Install Dependencies for Building Core**

Next, install the dependencies for building the `geth` (Go Ethereum) binary.

Run the following command:

```bash
make geth
```

This will download the necessary dependencies and build the `geth` binary. You should see output like:

```bash
>>> /usr/lib/go-1.22/bin/go build -ldflags "-X github.com/ethereum/go-ethereum/internal/version.gitCommit=afb8bd3ffe652e90a59af26db119bd988a03dd8f -X github.com/ethereum/go-ethereum/internal/version.gitDate=20250120 ..." -o /home/harystyles/core-chain/build/bin/geth ./cmd/geth
Done building.
Run "./build/bin/geth" to launch geth.
```

---

### **Step 5: Download and Extract the Blockchain Snapshot**

Instead of syncing from the genesis block (which can take a long time), it's recommended to use a snapshot of the blockchain data for faster syncing.

#### **Download the Testnet Snapshot**

You can download the latest snapshot from the Core snapshots repository:

[Core Snapshots GitHub](https://github.com/coredao-org/core-snapshots).

To download the snapshot directly from the terminal, use the following command:

```bash
wget https://snap.coredao.org/coredao-snapshot-testnet-20240327-pruned.tar.lz4
```

#### **Create Data Directory**

Create a directory for your node data if it hasn’t been created automatically:

```bash
mkdir -p ./node
```

#### **Decompress and Extract the Snapshot**

Decompress the snapshot using the `lz4` command and then extract it with `tar`:

```bash
lz4 -d coredao-snapshot-testnet-20240327-pruned.tar.lz4 coredao-snapshot-testnet-20240327-pruned.tar
tar -xvf coredao-snapshot-testnet-20240327-pruned.tar -C ./node
```

---

### **Step 6: Initialize the Genesis Block**

Now, you’ll initialize the genesis block for the Core Network. The `genesis.json` file should be provided in the repository or the Core documentation.

You can find the `genesis.json` and `config.toml` files in the **testnet2** release. Download and extract the files:

```bash
wget https://github.com/coredao-org/core-chain/releases/download/v1.0.14/testnet2.zip
unzip testnet2.zip
```

#### **Initialize the Genesis Block**

To initialize the node with the genesis block, run:

```bash
./build/bin/geth --datadir ./node init ./testnet2/genesis.json
```

Ensure the path to the `genesis.json` file is correct. In this case, `./testnet2/genesis.json` refers to the file located in the `testnet2` directory within your node directory.

---

### **Step 7: Start Your Node**

Now that everything is set up, you can start your node. There are two options for starting the node:

#### **Option 1: Start the Full Node with Options**

Run the following command:

```bash
./build/bin/geth --datadir ./node --cache 8000 --rpc.allow-unprotected-txs --networkid 1114
```

- `--datadir ./node`: Specifies where to store the blockchain data.
- `--cache 8000`: Allocates 8 GB of RAM for better performance.
- `--rpc.allow-unprotected-txs`: Allows unprotected transactions (needed for validator actions).
- `--networkid 1114`: Connects your node to the Testnet.

If you’re having trouble finding peers (i.e., the node can’t connect to other nodes), you can use the configuration file to help it start with bootstrap nodes.

#### **Option 2: Start the Node with the Configuration File**

Use the configuration file to make the process easier:

```bash
./build/bin/geth --config ./testnet2/config.toml --datadir ./node --cache 8000 --rpc.allow-unprotected-txs --networkid 1114
```

This command uses `config.toml`, located in the `testnet2` directory, to help the node connect to peers more easily.

---

### **Step 8: Monitor Logs and Performance**

Once your node is running, it's important to monitor the logs to ensure everything is operating smoothly.

#### **Monitor Logs**

The logs are typically stored in `./node/logs/core.log`. You can view them in real-time using:

```bash
tail -f ./node/logs/core.log
```

This will allow you to follow the log file as new entries are written.
