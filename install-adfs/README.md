# Installing an Active Directory Federated Services (ADFS) POC Environment

This describes the painful process of setting up an AD with Federated Services on a Windows Server VM. It is for testing the set-up of a Single-Sign On functionality.

## Get a Windows Server Environment

Ideally, we have a licenced Windows Server environment that we can work on. But some of us might be poor or are in organisations where the procurement process is painful, so we will use a free option - Windows Server Insider.

We'll need to:

1. Have a Microsoft Account
2. [Sign up for the Windows Insider Program](https://insider.windows.com/en-us/)
3. [Download the Windows Server Insider ISO](https://www.microsoft.com/en-us/software-download/windowsinsiderpreviewserver)
4. Install it in a VM (for this, around 10GB should be sufficient for the VM hard disk), preferably on a Windows host. This is because the Windows Server Insider build (as of the time of writing) is only Windows Server Core, so it does not have a GUI.
5. Download and install Windows Remote Server Administration Tools (RSAT) on the host machine to administer this environment (unless you want to use the command line all the time).

## Set Up the AD in the Server

After the server is installed, we need to set up the AD and add the AD role in the server. For the purposes of this POC environment, we can call the domain `contoso.local`. We'll need to run the following commands in powershell on the VM:

```powershell
Get-WindowsFeature AD-Domain-Services | Install-WindowsFeature
Import-Module ADDSDeployment
Install-ADDSForest
```

Optional: to set up a new user and add it as a domain admin:

```powershell
New-ADUser -Name “admin2” -GivenName admin2 -Surname admin2 -SamAccountName admin2 -UserPrincipalName admin2@contoso.local
Set-ADAccountPassword ‘CN=admin2,CN=users,DC=contoso,DC=local’ -Reset -NewPassword (ConvertTo-SecureString -AsPlainText “Password123” -Force)
Enable-ADAccount -Identity "CN=admin2,CN=users,DC=contoso,DC=local"
Add-ADGroupMember ‘Domain Admins’ "CN=admin2,CN=users,DC=contoso,DC=local"
```

Now that the AD is set up, we can administrate the server using the `contoso\Administrator` default account.

## Using RSAT

We'll need to run `ipconfig` inside the VM to get the IP of the VM, so we can connect to it from the host.

On the host machine, we can add the server in Server Manager using the IP. If you get a warning, just ignore it.

On the **host**, run the following first:

```powershell
Enable-VMIntegrationService -name Guest* -VMName {winservervm} -Passthru
```

Then add the server in the Server Manager. The Server Manager will try to connect to the server via Kerberos, which will fail. We can right click the server under the "All Servers" tab and choose "Manage As", to log in as `contoso\Administrator`

## Adding the Federation Service (FS) Role

Now we should be able to use RSAT to add the FS role.

1. We need an SSL cert because FS uses HTTPS to transport the claims. Since this is a lab environment, we can use openssl to do it. First, download and install [OpenSSL for Windows](https://slproweb.com/products/Win32OpenSSL.html) **on the host machine**. Then create a new folder somewhere. In this folder, you need to create a `req.cnf` file with the following contents. What is important here is the CN, DNS.1 and DNS.2 lines.

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
    CN = adfs1.contoso.local
    [v3_req]
    keyUsage = critical, digitalSignature, keyAgreement
    extendedKeyUsage = serverAuth
    subjectAltName = @alt_names
    [alt_names]
    DNS.1 = adfs1.contoso.local
    DNS.2 = enterpriseregistration.contoso.local
    DNS.3 = certauth.adsfs1.contoso.local
    ```

    Then, open Powershell in this folder and run the following:

    ```powershell
    openssl req -config req.cnf -new -x509 -sha256 -newkey rsa:2048 -nodes -keyout server.key -days 365 -out server.crt
    openssl pkcs12 -export -out server.pfx -inkey server.key -in server.crt  # convert to pfx format
    ```

2. Under All Servers, right click the VM and choose Add Roles and Features. Pretty simple, click next until we see the "Active Directory Federation Services", then choose that and follow the installation steps.

## Configuring the Federation Server

1. On the Server Manager Dashboard page, click the Notifications flag, and then click Configure the federation service on the server.
2. On the Welcome page, select Create the first federation server in a federation server farm, and then click Next.
3. On the Connect to AD FS page, specify an account with domain administrator rights (e.g. contoso\Administrator) for the contoso.local Active Directory domain that this computer is joined to, and then click Next. If the account doesn't have this rights, we can use the `Add-ADGroupMember ‘Domain Admins’ "CN=Administrator,CN=users,DC=contoso,DC=local"` command to add the account as a AD admin.
4. On the Specify Service Properties page, do the following, and then click Next.
    *  Import the SSL certificate that you have obtained earlier. This certificate is the required service authentication certificate. Browse to the location of your SSL certificate.
    * To provide a name for your federation service, type `adfs1.contoso.local`. This value is the same value that you provided when you enrolled an SSL certificate in Active Directory Certificate Services (AD CS).
    * To provide a display name for your federation service, type `Contoso Corporation`.
5. On the Specify Service Account page, create a new service account called `contoso\fsgmsa`.
6. On the Specify Configuration Database page, select Create a database on this server using Windows Internal Database, and then click Next all the way.
7. In a Powershell, run the following on the server (when prompted for the service account, use `contoso\fsgmsa$`):

    ```powershell
    Initialize-ADDeviceRegistration
    Enable-AdfsDeviceRegistration
    Set-AdfsGlobalAuthenticationPolicy -DeviceAuthenticationEnabled $true
    ```

## Exposing Ports on VM

We'll need to expose ports from the VM to enable these services to work. To do this, we'll need to set up our VM networking:

1. Create a VM network switch

    On the **host**, run:

    ```powershell
    New-VMSwitch -SwitchName “NATSwitch” -SwitchType Internal
    New-NetIPAddress -IPAddress 192.168.0.1 -PrefixLength 24 -InterfaceAlias “vEthernet (NATSwitch)”
    New-NetNAT -Name “NATNetwork” -InternalIPInterfaceAddressPrefix 192.168.0.0/24
    ```

    If we need to remove this network in the future, we can run this:

    ```powershell
    Remove-NetNAT -Name “NATNetwork”
    Remove-NetIPAddress -IPAddress 192.168.0.1
    Remove-VMSwitch -VMSwitch “NATSwitch”
    ```

2. Shut down the VM, go to the VM Manager and change the network adapter to this new network switch.

3. Configure the VM to use this new switch (replace 192.168.0.31 with whatever IP we want the guest machine to have), with a static IP

    On the **guest**:

    ```powershell
    New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.0.31 -PrefixLength 24 -DefaultGateway 192.168.0.1
    Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "208.67.222.222,208.67.220.220"
    ```

4. Open the ports required (replace 192.168.0.31 with the IP of the VM) e.g. port 80 for http, 443 for https, 389 for LDAP. On the **host**:

    ```powershell
    Add-NetNatStaticMapping -ExternalIPAddress "0.0.0.0/24" -ExternalPort 80 -Protocol TCP -InternalIPAddress "192.168.0.31" -InternalPort 80 -NatName NATNetwork
    Add-NetNatStaticMapping -ExternalIPAddress "0.0.0.0/24" -ExternalPort 443 -Protocol TCP -InternalIPAddress "192.168.0.31" -InternalPort 443 -NatName NATNetwork
    Add-NetNatStaticMapping -ExternalIPAddress "0.0.0.0/24" -ExternalPort 389 -Protocol TCP -InternalIPAddress "192.168.0.31" -InternalPort 389 -NatName NATNetwork
    ```
    
5. You should also add the `contoso.local` domain into your hosts file so that your PC can resolve the domain to the IP of the VM. To do this, open Notepad as administrator on your host machine, and open the `C:\Windows\System32\drivers\etc\hosts` file. Add the following lines to the file:

    ```
    192.168.0.31        contoso.local
    192.168.0.31        adfs1.contoso.local
    ```

If you wish to remove these port mappings, use `Get-NetNatStaticMapping` to retrieve the list of network port mappings, and then `Remove-NetNatStaticMapping -StaticMappingID {mapping_id}` to remove the mapping.

To test the connection, we can use `Get-ADUser` and try to search the AD via its IP address. On the **host** machine, run (replace 192.168.0.31 with whatever IP you assigned the VM):

```powershell
Get-ADUser -Server 192.168.0.31 -Filter * -Credential contoso\Administrator
```

If we can search the AD, it means the connection works.

## Configuring IIS Remotely

Installing ADFS will also install the IIS role on the server. However, we cannot remotely administer it by default. To do this, we need to do the following:

1. Ensure that IIS is installed on the host machine, so we can remotely administer the server. To do this, press start and search for `Turn Windows Features on or off`, and open it. Check `Internet Information Services`.
2. We also need to install [IIS Manager for Remote Administration](https://www.iis.net/downloads/microsoft/iis-manager) on the host machine to remotely administer the server.
3. Next, we need to enable remote administration on the server. To do this, we need to run the following in Powershell on the **guest**:
    ```powershell
    Install-WindowsFeature Web-Mgmt-Service
    Set-ItemProperty -Path  HKLM:\SOFTWARE\Microsoft\WebManagement\Server -Name EnableRemoteManagement  -Value 1
    Set-Service -name WMSVC  -StartupType Automatic
    Start-service WMSVC
    ```
4. Then, we should be able to open up IIS Manager on the host machine, and click "File > Connect to a Server", and use the IP of the server (192.168.0.31) to connect to the server (use the `contoso\Administrator` account to log in). Ignore the warning of the certificate.

## Configuring IIS

We'll need to do some further configuration of the IIS on the ADFS Server. We can use the remote connection to do it from our host.

1.  Open **Internet Information Services (IIS) Manager**, and expand the server connection.
2.  Go to **Application Pools**, right-click **DefaultAppPool** to select **Advanced Settings**. Set **Load User Profile** to **True**, and then click **OK**.
4.  Right-click **Default Web Site** to select **Edit Bindings**.
5.  Add an **HTTPS** binding to port **443** with the SSL certificate that you have installed.

If you have set all these up properly, you should be able to download the federation metadata at https://adfs1.contoso.com/federationmetadata/2007-06/federationmetadata.xml.

## (Unconfirmed) Configuring the ADFS Relying Party Trust

We'll need to configure the trust between the ADFS and the application.

1. Obtain the federation metadata from the application. The application should have some steps on how you can export the federation metadata.
2. Copy the file to the VM. Suppose we have the file in `C:\Users\User\Downloads\appfedmetadata.xml` on the host machine. We can copy it into the VM using Powershell **on the host**:

    ```powershell
    Copy-VMFile "winserver" -SourcePath "C:\Users\User\Downloads\appfedmetadata.xml" -DestinationPath "C:\Temp\appfedmetadata.xml" -CreateFullPath -FileSource Host -Force
    ```
    
3. Then we can add the relying party trust **on the guest/server** (replace the placeholder `name_of_relying_party` to whatever you have set - it must be the same between the ADFS and the application):

    ```powershell
    Add-ADFSRelyingPartyTrust -Name "{name_of_relying_party}" -MetadataFile "C:\Temp\appfedmetadata.xml" -IssuanceAuthorizationRules '@RuleTemplate = "AllowAllAuthzRule" => issue(Type = "http://schemas.microsoft.com/authorization/claims/permit", Value = "true");' -SignatureAlgorithm 'http://www.w3.org/2000/09/xmldsig#rsa-sha1' 
    ```
    
    The `SignatureAlgorithm` parameter can be either 'http://www.w3.org/2000/09/xmldsig#rsa-sha1' or 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256'
    
    If there is a need to remove this relying party trust later, we can run:
    
    ```powershell
    Remove-AdfsRelyingPartyTrust -TargetName "{name_of_relying_party}"
    ```
    
4. If the relying party application server is also some POC environment, then it likely has some self-signed cert as well which by default will be rejected by our server. We need to import it into our root CA. First, copy the cert from the host to the guest.

    On the **host** machine:
    ```powershell
    Copy-VMFile "winserver" -SourcePath "C:\Users\User\Downloads\appserver.cer" -DestinationPath "C:\Temp\appserver.cer" -CreateFullPath -FileSource Host -Force
    ```
    Then on the **guest** machine:
    ```powershell
    Import-Certificate -FilePath "C:\Temp\appserver.cer" -CertStoreLocation cert:\LocalMachine\Root
    ```
    You may have to import it into the AdfsTrustedDevices as well:
    ```powershell
    Import-Certificate -FilePath "C:\Temp\appserver.cer" -CertStoreLocation cert:\LocalMachine\AdfsTrustedDevices
    ```


## Troubleshooting

### Cannot find Server Manager after Installing RSAT

It might be in `C:\ProgramData\Microsoft\Windows\StartMenu\Programs`

### WinRM Authentication Error in Server Manager

I haven't managed to solve this problem except by getting the computer with Server Manager to join the domain of the AD.

1. Add the IP of the AD server as a DNS server (installing an AD will also install the DNS role), so the domain can be found through the DNS. This can be done by going to the Control Panel > Network and Internet > Network and Sharing Center > Change adapter settings > Right click the connection > select properties > Click on the IPv4 option and select Properties > Add the IP into the Preferred DNS Server
2. Next, we need to join the domain. Click on start > type in "This PC", right click on it and select properties > Click Change Settings > Use the Network ID wizard and follow the instructions to join the domain.
3. After this, we can add the server through the domain in Server Manager.