# online.net certbot hook
A shell script to be used for auth hook when issuing a certificate through certbot (https://letsencrypt.org) for domains managed by online.net (https://online.net)

This script was created with the intention of issuing wildcard domain certificates. For example: *.example.org
It is made to avoid creating multiple certificates for every sub-domain you own.
Nevertheless it should work perfectly fine for non-wildcard domains as well.

To be able to run this script, you will need:
 * 'jq' library (found here: https://github.com/stedolan/jq) 
 * 'certbot' from letsencrypt (found here: https://certbot.eff.org/)

### Be warned:
This script will automatically change your DNS settings. While it manages to revert back everything to how it was, there is absolutely no guarantee that everything will run flawless.
Due to the nature of how online.net API works, this script will make a new DNS zone version, add a new sub-domain, copy all data from your current active DNS zone version onto the new one and then activating it temporarily (effectively de-activating your current active one) while letsencrypt checks for its token, then re-activating the DNS zone version and finally deleting the temporary version created in this process.
It is a task that could fail at any time, so it's suggested to confirm after running this script that everything is how it should be.





# Issue an actual and valid certificate for your domain:
(if you want to test-run before the real action, read the next paragraph below)

To create a valid certificate, you need to run the following command:

```sh
ONLINE_NET_API_TOKEN="your_online_net_api_token_here" certbot certonly --agree-tos --manual --preferred-challenge=dns --manual-auth-hook=./onlinenet-certbot-hook.sh --email "email@example.org" --manual-public-ip-logging-ok -d "example.org" --server "https://acme-v02.api.letsencrypt.org/directory"
```

You should replace `your_online_net_api_token_here` with your online.net API token, `email@example.org` with your own e-mail and `example.org` with your own domain.
If you get the `'Directory field not found'` error, this means that your certbot version is older and you need to replace `https://acme-v02.api.letsencrypt.org/directory` with `https://acme.api.letsencrypt.org/directory`

After running the script and successfully getting a certificate, you can link it to your website and enjoy having that green lock icon on the browser.



# Testing the script:

This script is made to be run through the certbot command, but its suggested to run it individually just to confirm it works properly for you.
This is done because when you run it through certbot, you will not be able to see any output of this script.

First of all, you will need to get your API token from https://online.net, so head there, login to the console and find your token here: https://console.online.net/en/api/access
After getting your token, its time to test-run the script

```sh
CERTBOT_DOMAIN="example.org" CERTBOT_VALIDATION="this_is_a_dummy_token" ONLINE_NET_API_TOKEN="your_online_net_api_token_here" ./onlinenet-certbot-hook.sh
```

Replace with your domain instead of `example.org` and your online.net api token instead of `your_online_net_api_token_here`, then run the script.
If the script doesn't throw any errors like invalid API access or missing jq library or whatever, and runs successfully until the last line, then it is good to go.
If you see any error, either write an issue here, or try to solve it yourself by running the script on debug mode.



### Staging run for certification:


If you want to test-create a certificate, without getting any limitations from letsencrypt, you can run in staging mode (more information here: https://letsencrypt.org/docs/staging-environment/)
The basic shell command to do so is the following:

```sh
ONLINE_NET_API_TOKEN="your_online_net_api_token_here" certbot certonly --agree-tos --manual --preferred-challenge=dns --manual-auth-hook=./onlinenet-certbot-hook.sh --email "email@example.org" --manual-public-ip-logging-ok -d "example.org" --staging --server "https://acme-staging-v02.api.letsencrypt.org/directory"
```

Ofcourse, you should replace `your_online_net_api_token_here` with your online.net API token, `email@example.org` with your own e-mail and `example.org` with your own domain. 
Also, you might need to run this as root and grant executable mod to the script via `chmod +x onlinenet-certbot-hook.sh`

If your certbot is an older version, and you are getting this error:
`Starting new HTTPS connection (1): acme-staging-v02.api.letsencrypt.org
An unexpected error occurred:
KeyError: 'Directory field not found'`
You will need to replace `https://acme-staging-v02.api.letsencrypt.org/directory` with `https://acme-staging.api.letsencrypt.org/directory`.

If the script has failed, you will get similar log:
```
Waiting for verification...
Cleaning up challenges
Failed authorization procedure. example.org (dns-01): urn:acme:error:dns :: DNS problem: NXDOMAIN looking up TXT for _acme-challenge.example.org
```

Otherwise if everything is successful, you will get log looking something like this:

```
Waiting for verification...
Cleaning up challenges
Generating key (2048 bits): /etc/letsencrypt/keys/0007_key-certbot.pem
Creating CSR: /etc/letsencrypt/csr/0007_csr-certbot.pem

IMPORTANT NOTES:
 - Congratulations! Your certificate and chain have been saved at
   /etc/letsencrypt/live/example.org/fullchain.pem. Your cert will
   expire on 2018-09-14. To obtain a new or tweaked version of this
   certificate in the future, simply run certbot again. To
   non-interactively renew *all* of your certificates, run "certbot
   renew"
 - If you like Certbot, please consider supporting our work by:

   Donating to ISRG / Let's Encrypt:   https://letsencrypt.org/donate
   Donating to EFF:                    https://eff.org/donate-le
```
