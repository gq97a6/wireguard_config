# How to setup WireGuard VPN server

This guide contains instructions how to setup wiregurad server:
* Includes few useful bash scripts
* Explains basic iptables usage
* Teaches you how to use WireGuard both from client and server side

Scripts included in this repo:

* [setup_iptables.sh](setup_iptables.sh) - to configure iptables rules

> [!CAUTION]
> This script **WIPES ALL EXISTING RULES** and introduces **DROP BY DEFAULT** policy for all incoming and forwarding packets. **STOP ALL DOCKER CONTAINERS** before running this script.

These four scripts are meant to be stored with WireGuard configuration in **/etc/WireGuard**
* [apply_config.sh](apply_config.sh) - to reload WireGuard configuration
* [create_pair.sh](create_pair.sh) - to echo new public-private key pair
* [gen_client.sh](gen_client.sh) - to add new WireGuard client to existing setup
* [show_code.sh](show_code.sh) - display QR code for client config

> [!NOTE]  
> Usage is covered in [Scripts usage](#scripts-usage) section.

## Desired effect

This guide aims to create three VPN networks. Each with different level of trust.

### [wg0] - Highest level of trust
This network is meant to be used by devices with highest level of trust. You can setup other services to listen on this interface so they can be used only by devices in this network. For example SSH server that listens on interface 10.0.0.1 (wg0) so only devices in this network can access this server via SSH.

**Subnet for this network:** 10.0.0.0/24  
**Interface address:** 10.0.0.1  
**Client addresses:** from 10.0.0.2 to 10.0.0.254  
**Listen port:** 10000  

Devices in this network can access:
1. Internet
2. Devices in network wg0
3. Devices in network wg1
4. Devices in network wg2

### [wg1] - Limited/Conditional trust
**Subnet for this network:** 10.0.1.0/24  
**Interface address:** 10.0.1.1  
**Client addresses:** from 10.0.1.2 to 10.0.1.254  
**Listen port:** 10010  

Devices in this network can access:
1. Internet
2. ~~Devices in network wg0~~
3. Devices in network wg1
4. Devices in network wg2

### [wg2] - No trust
**Subnet for this network:** 10.0.2.0/24  
**Interface address:** 10.0.2.1  
**Client addresses:** from 10.0.2.2 to 10.2.0.254  
**Listen port:** 10020  

Devices in this network can access:
1. ~~Internet~~
2. ~~Devices in network wg0~~
3. ~~Devices in network wg1~~
4. ~~Devices in network wg2~~

## Steps overview and requirements
0. Install iptables (not covered)
1. Install WireGuard
2. Setup firewall rules
3. Setup WireGuard

## Step 1. Install WireGuard
Full guide how to install WireGuard is coverd on WireGuard website [here](www.WireGuard.com/install).
```bash
apt install WireGuard
```

## Step 2. Setup firewall rules
This step is required for WireGuard to work and to enforce rules specified in [Desired effect](#desired-effect)

> [!CAUTION]
> Modifying iptables rules can cause loss of SSH access and disrupt network services, potentially locking you out of your system and exposing it to security risks. It's highly recommended to use other than SSH means to access your server to setup VPN.

> [!CAUTION]
> Iptables rules are not persisting between system reboots by default. This issue is addressed in later steps.

> [!CAUTION]
> This guide includes [script](setup_iptables.sh) to setup iptables rules for you. This script **WIPES ALL EXISTING RULES** and introduces **DROP BY DEFAULT** policy for all incoming and forwarding packets. **STOP ALL DOCKER CONTAINERS** and possibly other network services before running this script. Use it **ONLY** if you understand fully how it works and what it does. Remember to open other ports that are not covered in this script if needed.

> [!IMPORTANT]
> Docker uses iptables to configure container networks.
> This configuration is done each time docker service starts thus docker iptalbes rules should not be included in persistent iptables configuration. Docker also introduces new rules if needed to open ports for containers, so you don't have to worry about **DROP BY DEFAULT** policy. After setting up iptables rules you can run this command to recover all iptables rules required by docker:
```bash
sudo systemctl restart docker
```

### Iptables usage
As stated before you can use this [script](setup_iptables.sh) to setup all rules if you fully understands what it does. If thats not the case, below is basic introduction guide to iptables.
```bash
bash setup_iptables.sh
```

Iptables rules are sorted into tables. Each table has its own chains. You can also add custom chains to specific table.

1. **FILTER** table  
One of the most commonly used tables in iptables is the filter table.  
The filter table determines whether a packet should be allowed to continue to its intended destination or denied.  
**This table contains following chains**:  
    * INPUT
    * OUTPUT
    * FORWARD

2. **NAT** table  
This table is used for Network Address Translation (NAT). It is used to manipulate packets that create new connections.
We will insert new rules in this table to allow internet access through eth0 for some devices.  
**This table contains following chains**:  
    * OUTPUT
    * PREROUTING
    * POSTROUTING

3. **MANGLE** and **RAW** tables less important for this guide

The default table is **FILTER** table when using iptables command without specifing the table with flag:
```bash
-t nat
```

To remove (flush) all rules in specific table use:
```bash
iptables -F -t table
```

To remove all user defined chains in specific table use:
```bash
iptables -X -t table
```

Policy is a default action that iptables will take if no rule fires.
* **ACCEPT** policy means packets gets accepted by default
* **DROP** policy means packet gets dropped silently with no indication being sent to the client
* **REJECT** means the packet is rejected with indication being sent to the client

To set policy for default table (filter) in all chains use:
```bash
iptables -P INPUT DROP
iptables -P OUTPUT ACCEPT
iptables -P FORWARD DROP
```

To create new user defined chain. This is not required, we could insert new rules directly into built-in chains but this way we can seperate our rules from for example those created by Docker:
```bash
iptables -N _INPUT
iptables -N _OUTPUT
iptables -N _FORWARD
iptables -N _POSTROUTING -t nat
```

To append user defined chains into specific existing chains:
```bash
iptables -A INPUT -j _INPUT
iptables -A OUTPUT -j _OUTPUT
iptables -A FORWARD -j _FORWARD
iptables -A POSTROUTING -t nat -j _POSTROUTING
```

We want to block access to our services from the outside. Yet this way no connection could be established, we would be able to only send packets but any response would be blocked by firewall. For example ping requests comming back to our server.  
Thus we have to accept RELATED and ESTABLISED connections:
```bash
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

To accept all traffic coming from the loopback interface (localhost):
```bash
iptables -A _INPUT -i lo -j ACCEPT
```

Below are rules to configure WireGuard interfaces described in [Desired effect](#desired-effect):
```bash
#WireGuard [wg0] (10.0.0.0/24) -------------------------------------------------------------------------

#Allow all trafic from devices in this network
iptables -I _FORWARD -s 10.0.0.0/24 -j ACCEPT
iptables -I _INPUT -s 10.0.0.0/24 -j ACCEPT

#Open port for this network
iptables -A _INPUT -i eth0 -p udp --dport 10000 -j ACCEPT

#Allow internet access
iptables -A _POSTROUTING -t nat -s 10.0.0.0/24 -o eth0 -j MASQUERADE

#WireGuard [wg1] (10.0.1.0/24) -------------------------------------------------------------------------

#Allow traffic to other devices in wg1 and wg2
iptables -A _FORWARD -i wg1 -o wg1 -j ACCEPT
iptables -A _FORWARD -i wg1 -o wg2 -j ACCEPT

#Open port for this network
iptables -A _INPUT -i eth0 -p udp --dport 10010 -j ACCEPT

#Allow internet access
iptables -A _FORWARD -i wg1 -o eth0 -j ACCEPT
iptables -A _POSTROUTING -t nat -s 10.0.1.0/24 -o eth0 -j MASQUERADE

#WireGuard [wg2] (10.0.2.0/24) -------------------------------------------------------------------------

iptables -A _INPUT -i eth0 -p udp --dport 10020 -j ACCEPT
```

### Persistent iptables configuration
There are many ways to make iptables configuration persistent. One way is to use **iptables-persistent**:
```bash
sudo apt install iptables-persistent
sudo iptables-save > /etc/iptables/rules.v4
sudo ip6tables-save > /etc/iptables/rules.v6
```

## WireGuard
Basic WireGuard configuration is simple:  
* Configuration files are strored in `/etc/WireGuard`
* Each interface and client has its own public-private key pair.  
* Server configuration includes client's public keys and server private key.  
* Client configuration includes server public keys and client's public key.

Example configuration with no clients:
```ini
[Interface]
Address = 10.0.0.1/24

ListenPort = 10000
PrivateKey = MIZ3hBiSW9QifxCXou2xbNgXjrKzAl/gnN3tnYbjrEw=
```

To allow clients to connect to the server we need to specify this client in server configuration.  
**AllowedIPs** specifies client IP in this VPN network.
```ini
[Interface]
Address = 10.0.0.1/24

ListenPort = 10000
PrivateKey = MIZ3hBiSW9QifxCXou2xbNgXjrKzAl/gnN3tnYbjrEw=

#client
[Peer]
PublicKey = 9exB+zTsAsXsxvBf0PnxZAotSsHGLdi5N3zdfJSQVVk=
AllowedIPs = 10.0.0.2/32
```

Example client configuration. It includes client private key, it's address and server public key. **AllowedIPs** specifiy which packets will be router through VPN.  
When you set `AllowedIPs = 10.0.0.0/16`, it means that any traffic destined for IP addresses within the range 10.0.0.0 to 10.0.255.255 will be routed through the VPN.  
You can set `AllowedIPs = 0.0.0.0/0` to route all client traffic through VPN.

```ini
[Interface]
PrivateKey = +FTOaAcYjnO3hMem28IJQ1y0EJF+mv1SAg9KJKf/n2M=
Address = 10.0.1.1/24
DNS = 8.8.8.8

[Peer]
PublicKey = +qS23O41KJDcFXz9J5Bh4xbQVntY1s1R9jLUfm21whY=
AllowedIPs = 10.0.0.0/16
Endpoint = 182.19.249.223:10010
PersistentKeepalive = 25
```

To list all WireGuard interfaces
```bash
sudo wg
```

To load WireGuard configuration
```bash
sudo wg-quick up wg0
```

To stop WireGuard interaface
```bash
sudo wg-quick down wg0
```

## Step 3. Setup WireGuard

1. Copy all required scripts and configuration files from this repository to **/etc/WireGuard**.
2. Generate public-private key pairs for each interface with [create_pair.sh](create_pair.sh).

3. Edit interfaces private keys in each interface configuration.
```ini
PrivateKey = ???
```

4. Edit interfaces public keys in [gen_client.sh](gen_client.sh).
```bash
case $INTERFACE_INDEX in
    0)
        SERVER_PUBLIC_KEY="???"
        SERVER_PORT="10000"
        ;;
    1)
        SERVER_PUBLIC_KEY="???"
        SERVER_PORT="10010"
        ;;
    2)
        SERVER_PUBLIC_KEY="???"
        SERVER_PORT="10020"
        ;;
    *)
        echo "Invalid interface number"
        exit 1
        ;;
esac
```

5. Insert server IP address in client config template in [gen_client.sh](gen_client.sh).
```ini
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = 10.0.$INTERFACE_INDEX.$CLIENT_HOST/24
DNS = 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
AllowedIPs = 10.0.0.0/16
Endpoint = ???:$SERVER_PORT
PersistentKeepalive = 25
EOL
```

6. How to add clients is covered in [Scripts usage](#scripts-usage) section.

7. Load WireGuard configuration
```bash
sudo wg-quick up wg0
sudo wg-quick up wg1
sudo wg-quick up wg2
```

8. To make wireguad configuration persist accross system reboots
```bash
sudo systemctl start wg-quick@wg0
sudo systemctl enable wg-quick@wg0

sudo systemctl start wg-quick@wg1
sudo systemctl enable wg-quick@wg1

sudo systemctl start wg-quick@wg2
sudo systemctl enable wg-quick@wg2
```

## Scripts usage

### [apply_config.sh](apply_config.sh) - to reload WireGuard configuration
```bash
foo@bar:~$ bash apply_config.sh 2
[#] ip link delete dev wg2
[#] ip link add wg2 type WireGuard
[#] wg setconf wg2 /dev/fd/63
[#] ip -4 address add 10.0.2.1/24 dev wg2
[#] ip link set mtu 1420 up dev wg2
```

### [create_pair.sh](create_pair.sh) - to echo new public-private key pair
```bash
foo@bar:~$ bash create_pair.sh
PRIVATE: sEwq9N2y4qGkEQGx0ifjc86AW64XFqtt0jNASW0ADFA=
PUBLIC: sNZyEAAJYvJuO7QlQFfB+j/5nGjWpEg5vYMfgn8O8C8=
```

### [show_code.sh](show_code.sh) - display QR code for client config stored in `client_configs` folder
```bash
foo@bar:~$ bash show_code.sh client
█████████████████████████████████████████████████████████████████
█████████████████████████████████████████████████████████████████
████ ▄▄▄▄▄ █▄█▄▄█▀▀▀▄██▄ ███▄ ▀▄▀▀   ▀ █  ▄▄███ █▀▄ ██ ▄▄▄▄▄ ████
████ █   █ ████ █▀ ▄▀▄ ▀▀▀▀▄▀███▄▀▄ ▀▄█ ▀  █▀▀▄  █▄ ██ █   █ ████
████ █▄▄▄█ ██ ██ ▀▀█▄▄▄▀▄▄█▀█▀ ▄▄▄ ▀█▄▀ ▀▄█▄▀█▄▀▄▀▀▄██ █▄▄▄█ ████
████▄▄▄▄▄▄▄█ █▄▀ ▀ ▀ ▀ ▀ █ ▀▄▀ █▄█ ▀▄█ █ █▄█▄█▄█ ▀▄█▄█▄▄▄▄▄▄▄████
████  ▀ ▄▀▄█▀▀██▄ ▀█ █  █▄ ██▄▄ ▄   ▀▀ ██  █▄███▀█ █▀▀ █████ ████
█████ █▄██▄▀▀▄█▄▀▀▄██▀██▄ ▀▄▄ █▄▄██▄▀▄ ▀█▀██ ▄ ▀▄▄▄█▄██▄██▀▀▄████
█████ ██ ▄▄ █▀ ▄█▄ ▄██▀▄█ ▄ ▀▀▀ ▄ ██▄ █▄▄▄  █▀  ▄ █▄ ▀▄█  ▄▀█████
█████ ▄▄▄█▄███▄█▄ ▄▄▀█▄█▀▄▄▄▀ ▄▄▀▀  ▀█▀█▀█▀  █ ▄▀█  ▄▄ ▄▄▄ ▄█████
█████ ▄█▄▀▄▄██▄█  █ ▀▀▄ ▄▀▀▄▀██▄▀▄▀▄▄▀██▀▀██▀█ █ ▄▀▀▀▄▄    ▀▀████
████▄ ██▀▄▄▀▄▀▀█▀▀█ █▄▄▀▀ ▀▀▀▀██▄▄▀▄▄▄   ▀▀▄ ▄█▄██ ▄▄▄ █▄█▄▄ ████
████   ▀██▄ ▀▀ ▄▀█ █ ▄  █  ▄ ▀▀█▄▀█ ▀▄█ ▄▀█   ▄▀▀▀▄ ▀   ▀▄▄▀ ████
█████▀▀ █▀▄█ ▄   ▄██▀  ▀▀▄▄▀ █▀▄█▀▄█▄ █▀ ▀ █▄  █▄ ▀ ▀▀█ █    ████
████ ▀▀▄█▀▄▀▀ ▀▄ ▄▀█ ▄ ▄▀▄█ ▄ █  ██▄▀▄ ▀▀▀ ▄█▄   ███▀█ █▄▄▄█▀████
████ ▀█▄ ▄▄▄ ▄▀███ ██▀ ▀▀███ █ ▄▄▄ █▄▄▀▄▀▄ █▀█▄ █▄ █ ▄▄▄    ▄████
████▀█ ▄ █▄█ █ ▀████▀▄ █▄█ ▀ ▀ █▄█     █▄█▄███▀█  ▀  █▄█  █▀█████
███████▀▄ ▄ ▄█▀█▄████▀▄▀▄▄███▄ ▄  ▄ ▀██▄▀▀▀▄▀▄▀ ██▀█▄▄▄ ▄ ▀█▄████
████ ▀███ ▄▄ ▄▀▀▄█▀▀ ▄▄█ ▀▄▀▀▄▀  ▄▀▀ ▀ ▀ ▄▄███ ▄▀█▄██ █▀▀█▄▄▀████
█████▄▀   ▄▀██▄▄▄▄▄▄█▄█ ▄▄▄▄▀▀▀▀▀ █▀ █▄ █▄  █ ▀█ ██▄▀  ▀▀ ▀ ▄████
█████▄▄ ▄▄▄▀█▄▀  ▄▄  ▄█▀ ▀▄ ▄ ▄▄▀ ▄▀ ▀ ▀ ▀█▄▄▀█▀▄ █▀  ▀ █ ▄▀ ████
█████▀▀█▄█▄▄█  █ ▄▄ ██▄█▀  ▀█▄▀▀▀▄ ██ █▄█▀█▄ ▄ █▀▀ ██▄▀▄█ ▀█▀████
████▀█ ▀██▄█▀█ ▄▄▄▀▀▀▀▀█▄▀▀  █ ▄  ██▄▄█ ▀▀█▄██▀█▀ ▀█▀▀▄▄ ▄▄▀▄████
████ █▄▄█▀▄▄ ▀█  ███▄██ █ ▄█▄ ▀█▀▄▀▀▀ ██▀▄▀▄█  ██▄▄▀ ▀▄▄▀ ▀▀▄████
████▄█ █  ▄▀█▄ █▄ ▀█ ▄▀ █  ███▀▄▀▀█▄█ ▀▀▀  ▄▄   █ ▀▀▀ █ ▀▄▀  ████
████ ▀ ▀▀▄▄▀ ▀▄█▄███ ██▄▀██▀▀▄ █  ▄▀ ▄  █▄▀▄▀██▀▄  ▄▄   ▀█ ▀ ████
██████████▄█ █ █ █▄▀█ ▄█ █   ▄ ▄▄▄ █ ▀ ▀▀▀ ▄▄█▀█ ▀▄  ▄▄▄ ▄█ ▀████
████ ▄▄▄▄▄ ██▀▀▀ ▀▄█▄███▄ ██▀  █▄█ ▄█▄▄█▄▄█▄▄█▀ █▄▄▄ █▄█ ▀▀▀█████
████ █   █ █ ██▄▀▄▄█▀▀▄▀ ▄█  █▄▄▄▄  ▄ ▀▀▄▄  ▀ █ ▄▀▄  ▄▄▄▄▀█▄▄████
████ █▄▄▄█ █▀█ ▀██ █▄▄▄▄█▄▄▄ ▄ █ ▄ ▀▀▀ █ ▄▄▄█▄▀▄▀▄   █▀█▄▄   ████
████▄▄▄▄▄▄▄█▄██▄█▄██▄██▄▄▄▄███▄▄▄█▄▄█▄███▄▄█▄▄▄█▄██▄████▄█▄██████
█████████████████████████████████████████████████████████████████
█████████████████████████████████████████████████████████████████
```
### [gen_client.sh](gen_client.sh) - to add new WireGuard client to existing setup
```bash
foo@bar:~$ bash gen_client.sh
Usage: gen_client.sh <client_name> <client_host> <interface_index>

foo@bar:~$ bash gen_client.sh client 1 1
#client
[Peer]
PublicKey = TaqXNqLjQ27nuZzVJT8KN9Z2/B0IOoFNx88NI7BpXFo=
AllowedIPs = 10.0.1.1/32
```

Recommended way to use this script is to open configuration file with nano then use `CTRL + T` shortcut. Output of the command used will be pasted into editor.
```bash
nano /etc/WireGuard/wg0
```

Then save the file and run [apply_config.sh](apply_config.sh) to apply new configuration.  
Script outputs generated client configs into `client_configs` folder.
