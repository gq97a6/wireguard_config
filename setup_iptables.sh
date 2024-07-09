#Remove every rule
iptables -F -t filter
iptables -F -t nat
iptables -F -t mangle
iptables -X -t filter
iptables -X -t nat
iptables -X -t mangle

#Set policy
iptables -P INPUT DROP
iptables -P OUTPUT ACCEPT
iptables -P FORWARD DROP

#Group rules into chains
iptables -N _INPUT
iptables -N _OUTPUT
iptables -N _FORWARD
iptables -N _POSTROUTING -t nat

#Append chains
iptables -A INPUT -j _INPUT
iptables -A OUTPUT -j _OUTPUT
iptables -A FORWARD -j _FORWARD
iptables -A POSTROUTING -t nat -j _POSTROUTING

#Allow related and established connections
iptables -A _INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -A _FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

#Accept all traffic coming from the loopback interface (localhost):
iptables -A _INPUT -i lo -j ACCEPT

#Wireguard [wg0] (10.0.0.0/24) -------------------------------------------------------------------------

#Allow all trafic from devices in this network
iptables -I _FORWARD -s 10.0.0.0/24 -j ACCEPT
iptables -I _INPUT -s 10.0.0.0/24 -j ACCEPT

#Open port for this network
iptables -A _INPUT -i eth0 -p udp --dport 10000 -j ACCEPT

#Allow internet access
iptables -A _POSTROUTING -t nat -s 10.0.0.0/24 -o eth0 -j MASQUERADE

#Wireguard [wg1] (10.0.1.0/24) -------------------------------------------------------------------------

#Allow traffic to other devices in wg1 and wg2
iptables -A _FORWARD -i wg1 -o wg1 -j ACCEPT
iptables -A _FORWARD -i wg1 -o wg2 -j ACCEPT

#Open port for this network
iptables -A _INPUT -i eth0 -p udp --dport 10010 -j ACCEPT

#Allow internet access
iptables -A _FORWARD -i wg1 -o eth0 -j ACCEPT
iptables -A _POSTROUTING -t nat -s 10.0.1.0/24 -o eth0 -j MASQUERADE

#Wireguard [wg2] (10.0.2.0/24) -------------------------------------------------------------------------

iptables -A _INPUT -i eth0 -p udp --dport 10020 -j ACCEPT

#Logging -----------------------------------------------------------------------------------------------

#Log new accepted on wireguard ports
#iptables -I _INPUT -i eth0 -p udp --dport 10000 -m conntrack --ctstate NEW -m limit --limit 1/s -j LOG --log-prefix "WIREGUARD_NEW_WG0: " --log-level 7
#iptables -I _INPUT -i eth0 -p udp --dport 10010 -m conntrack --ctstate NEW -m limit --limit 1/s -j LOG --log-prefix "WIREGUARD_NEW_WG1: " --log-level 7
#iptables -I _INPUT -i eth0 -p udp --dport 10020 -m conntrack --ctstate NEW -m limit --limit 1/s -j LOG --log-prefix "WIREGUARD_NEW_WG2: " --log-level 7

#Log dropped on _FORWARD
#iptables -A _FORWARD -m limit --limit 1/s -j LOG --log-prefix "IPTABLES_FRWD_DROP: " --log-level 7
