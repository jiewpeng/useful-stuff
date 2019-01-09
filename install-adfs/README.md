# Installing an Active Directory Federated Services (ADFS) POC Environment

This describes the painful process of setting up an AD with Federated Services on a Windows Server VM. It is for testing the set-up of a Single-Sign On functionality.

## Get a Windows Server Environment

Ideally, we have a licenced Windows Server environment that we can work on. But some of us might be poor or are in organisations where the procurement process is painful, so we will use a free option - Windows Server Insider.

We'll need to:

1. Have a Microsoft Account
2. [Sign up for the Windows Insider Program](https://insider.windows.com/en-us/)
3. [Download the Windows Server Insider ISO](https://www.microsoft.com/en-us/software-download/windowsinsiderpreviewserver)
4. Install it in a VM, preferably on a Windows host. This is because the Windows Server Insider build (as of the time of writing) is only Windows Server Core, so it does not have a GUI.
5. Download and install Windows Remote Server Administration Tools (RSAT) to administer this environment (unless you want to use the command line all the time).

## Set Up the AD in the Server

After the server is installed, we need to set up the AD and add the AD role in the server. We'll need to run the following commands:

```powershell
Get-WindowsFeature AD-Domain-Services | Install-WindowsFeature
Import-Module ADDSDeployment
Install-ADDSForest
```

Optional: to set up a new user and add it as a domain admin:

```powershell
New-ADUser -Name “admin2” -GivenName admin2 -Surname admin2 -SamAccountName admin2 -UserPrincipalName admin2@contoso.com
Set-ADAccountPassword ‘CN=admin2,CN=users,DC=contoso,DC=com’ -Reset -NewPassword (ConvertTo-SecureString -AsPlainText “Password123” -Force)
Enable-ADAccount -Identity "CN=admin2,CN=users,DC=contoso,DC=com"
Add-ADGroupMember ‘Domain Admins’ "CN=admin2,CN=users,DC=contoso,DC=com"
```

Now that the AD is set up, we can administrate the server using the `contoso\Administrator` default account.

## Using RSAT

We'll need to run `ipconfig` inside the VM to get the IP of the VM, so we can connect to it from the host.

On the host machine, we can add the server using the IP. If you get a warning, just ignore it.

Not sure if this is needed, but if connecting to the IP does not work, we may have to run the following (replace `winservervm` with whatever the VM name is):

```powershell
Enable-VMIntegrationService -name Guest* -VMName {winservervm} -Passthru
```

The Server Manager will try to connect to the server via Kerberos, which will fail. We can right click the server under the "All Servers" tab and choose "Manage As", to log in as `contoso\Administrator`

## Adding the Federation Service (FS) Role

Now we should be able to use RSAT to add the FS role.

1. Before we can set up FS, we need to set up a service account for it (note that when searching for service account users, we need to append their name with a $ sign e.g. FsGmsa$):
```powershell
Add-KdsRootKey -EffectiveTime (Get-Date).AddHours(-10)
New-ADServiceAccount FsGmsa -DNSHostName adfs1.contoso.com -ServicePrincipalNames http/adfs1.contoso.com
```
2. We also need an SSL cert because FS uses HTTPS to transport the claims. Since this is a lab environment, we can use openssl to do it. I would use a Docker container, install openssl on it and then use it from there. For example, we can launch a container using `docker run --rm -it -v "${PWD}:/work" nginx" /bin/bash`, and within it run:
```bash
apt-get update && apt-get install -y openssl
openssl genrsa -des3 -out /work/server.key 2048  # generate private key
openssl req -new -key /work/server.key -sha256 -out /work/server.csr  # generate a certificate signing request, which is sent to a certification authority
openssl x509 -req -days 3650 -config /work/req.cnf -in /work/server.csr -signkey /work/server.key -sha256 -out /work/server.crt  # sign the certificate
openssl pkcs12 -export -out /work/server.pfx -inkey /work/server.key -in /work/certificate.crt  # convert to pfx format
```
Before that, we need to create a `req.cnf` file in the current directory on the host. What is important here is the CN, DNS.1 and DNS.2 lines.
```
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
C = SG
ST = SG
L = Singapore
O = MyCompany
OU = MyDivision
CN = adfs1.contoso.com
[v3_req]
keyUsage = critical, digitalSignature, keyAgreement
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = adfs1.contoso.com
DNS.2 = enterpriseregistration.contoso.com
DNS.3 = certauth.adsfs1.contoso.com
```
3. Under All Servers, right click the VM and choose Add Roles and Features. Pretty simple, click next until we see the "Active Directory Federation Services", then choose that and follow the installation steps.

## Configuring the Federation Server

1. On the Server Manager Dashboard page, click the Notifications flag, and then click Configure the federation service on the server.
2. On the Welcome page, select Create the first federation server in a federation server farm, and then click Next.
3. On the Connect to AD FS page, specify an account with domain administrator rights (e.g. contoso\Administrator) for the contoso.com Active Directory domain that this computer is joined to, and then click Next. If the account doesn't have this rights, we can use the `Add-ADGroupMember ‘Domain Admins’ "CN=Administrator,CN=users,DC=contoso,DC=com"` command to add the account as a AD admin.
4. On the Specify Service Properties page, do the following, and then click Next.
  *  Import the SSL certificate that you have obtained earlier. This certificate is the required service authentication certificate. Browse to the location of your SSL certificate.
  * To provide a name for your federation service, type adfs1.contoso.com. This value is the same value that you provided when you enrolled an SSL certificate in Active Directory Certificate Services (AD CS).
  * To provide a display name for your federation service, type Contoso Corporation.
5. On the Specify Service Account page, select Use an existing domain user account or group Managed Service Account, and then specify the GMSA account `contoso\FsGmsa$` that you created when you created the domain controller. If it doesn't work, choose to create a new one.
6. On the Specify Configuration Database page, select Create a database on this server using Windows Internal Database, and then click Next all the way.
7. In a Powershell, run the following on the server:
```powershell
Initialize-ADDeviceRegistration  # specify contoso\fsgmsa$ as the service acc
Enable-AdfsDeviceRegistration
Set-AdfsGlobalAuthenticationPolicy -DeviceAuthenticationEnabled $true
```

## Exposing Ports on VM

We'll need to expose ports from the VM to enable these services to work. To do this, we'll need to set up our VM networking:

1. Create a VM network switch
```powershell
New-VMSwitch -SwitchName “NATSwitch” -SwitchType Internal
New-NetIPAddress -IPAddress 192.168.0.1 -PrefixLength 24 -InterfaceAlias “vEthernet (NATSwitch)”
New-NetNAT -Name “NATNetwork” -InternalIPInterfaceAddressPrefix 192.168.0.0/24
```
2. Configure the VM to use this new switch (replace 192.168.0.31 with whatever IP we want the guest machine to have), with a static IP
```powershell
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.0.31 -PrefixLength 24 -DefaultGateway 192.168.0.1
Get-VMNetworkAdapter -VMName {winservervm} -Name "Network Adapter" | Set-VMNetworkConfiguration -IPAddress 192.168.0.31 -Subnet 255.255.255.0 -DNSServer 208.67.222.222 -DefaultGateway 192.168.0.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "208.67.222.222,208.67.220.220"
```
3. Open the ports required (replace 192.168.0.31 with the IP of the VM) e.g. port 80 for http, 443 for https, 389 for LDAP
```powershell
Add-NetNatStaticMapping -ExternalIPAddress "0.0.0.0/24" -ExternalPort 80 -Protocol TCP -InternalIPAddress "192.168.0.31" -InternalPort 80 -NatName NATNetwork
Add-NetNatStaticMapping -ExternalIPAddress "0.0.0.0/24" -ExternalPort 443 -Protocol TCP -InternalIPAddress "192.168.0.31" -InternalPort 443 -NatName NATNetwork
Add-NetNatStaticMapping -ExternalIPAddress "0.0.0.0/24" -ExternalPort 389 -Protocol TCP -InternalIPAddress "192.168.0.31" -InternalPort 389 -NatName NATNetwork
```

To test the connection, we can use Windows Admin Center as some form of way where we have a "web app" being served from the VM, and we can test if we can connect to this web app (and hence the VM).

1. Download  Windows Admin Center
2. Run the following from the host (replace the placeholders in the curly braces):
```powershell
Copy-VMFile “Server2019” -SourcePath “C:\Users\{User}\Downloads\WindowsAdminCenter{1804}.msi” -DestinationPath “C:\temp\WindowsAdminCenter{1804}.msi” -CreateFullPath -FileSource Host
```
3. Run the following in the VM (replace the placeholder in the curly braces):
```powershell
msiexec /i c:\temp\WindowsAdminCenter{1804}.msi /qn /L*v log.txt SME_PORT=443 SSL_CERTIFICATE_OPTION=generate
```
4. Navigate to https://localhost (Windows Admin Center is served on this)
