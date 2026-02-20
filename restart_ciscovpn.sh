


The Best Practice
Check the Conflict (Netskope vs. Cisco VPN)
In most corporate setups (like Rakuten's likely architecture), Cisco AnyConnect handles the internal network, and Netskope secures the web. They often fight.

Verify DNS Routing:
Run this to see if your Mac even knows how to find the company server IP:

bash

scutil --dns | grep "rakuten"

If this returns nothing: Your Cisco VPN is not pushing the DNS settings correctly. Restart Cisco AnyConnect.

If this returns an IP: The route exists, but Netskope is blocking the packets.

The "Order of Operations" Fix:
Sometimes the "hook" order gets messed up. Try this specific restart sequence:

Disconnect Cisco AnyConnect.
Kill Netskope (using the command I gave you previously).
Wait for Netskope to reload and stabilize (ensure the icon is solid).
Connect Cisco AnyConnect last.
Why? This forces Cisco to layer its VPN interface on top of the Netskope filter, ensuring company traffic goes inside the VPN tunnel before Netskope can touch it.


sudo launchctl unload -w /Library/LaunchDaemons/com.netskope.client.auxsvc.plist

sudo pkill -9 -f stAgentNE; sudo pkill -9 -f Netskope

sudo pkill -9 -f stAgent; sudo pkill -9 -f Netskope; sudo pkill -9 -f nsAppflow


# flush DNS
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder

# restart interface
sudo ifconfig en0 down; sleep 2; sudo ifconfig en0 up




