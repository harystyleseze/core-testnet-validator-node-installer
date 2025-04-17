1. Create service account and data directory
Create a service user for the execution service, create data directory and assign ownership. call the user sudocore

sudo adduser --system --no-create-home --group sudocore
sudo mkdir -p /var/lib/geth
sudo chown -R execution:execution /var/lib/geth

2. Install binaries

Install Go dependencies

wget -O go.tar.gz https://go.dev/dl/go1.19.6.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go.tar.gz
echo export PATH=$PATH:/usr/local/go/bin >> $HOME/.bashrc
source $HOME/.bashrc

Verify Go is properly installed by checking the version and cleanup files.

go version
rm go.tar.gz

Install build dependencies.

sudo apt-get update
sudo apt install build-essential git


Build the binary.


# Get new tags
git fetch --tags
# Get latest tag name
latestTag=$(git describe --tags `git rev-list --tags --max-count=1`)
# Checkout latest tag
git checkout $latestTag
# Build
make geth
Install the binary.

sudo cp $HOME/path-to-build/build/bin/geth /usr/local/bin

3. Setup and configure system

Create a systemd unit file to define your execution.service configuration.

sudo nano /etc/systemd/system/sudocore.service
Paste the following configuration into the file.

Copy
[Unit]
Description=Core Dao Node Setup
Wants=network-online.target
After=network-online.target
Documentation=https://docs.coredao.org

[Service]
Type=simple
User=sudocore
Group=sudocore
Restart=on-failure
RestartSec=3
KillSignal=SIGINT
TimeoutStopSec=900
ExecStart=/usr/local/bin/geth \
    --holesky \
    --port 30303 \
    --http.port 8545 \
    --authrpc.port 8551 \
    --maxpeers 50 \
    --metrics \
    --http \
    --datadir=/var/lib/geth \
    --pprof \
    --state.scheme=path \
    --authrpc.jwtsecret=/secrets/jwtsecret
   
[Install]
WantedBy=multi-user.target
To exit and save, press Ctrl + X, then Y, then Enter.

Run the following to enable auto-start at boot time.

Copy
sudo systemctl daemon-reload
sudo systemctl enable execution
Finally, start your execution layer client and check it's status.

Copy
sudo systemctl start execution
sudo systemctl status execution
Press Ctrl + C to exit the status.