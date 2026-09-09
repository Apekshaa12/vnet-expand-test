Document:
Azure vnet expansion Automation usecase enhancement


Table of Contents
Document:	1
Azure vnet expansion Automation usecase enhancement	1
Document Information	2
Author	2
Reviewers	2
Document History	2
Overview:	3
Details:	3
EUR Region:	5
AOA Region:	5
Conclusion:	6








Document Information
Author
NAME	ROLE	CONTACT NUMBER
Monse Raj Paramundayil
	Wipro Technical lead	Monse.raj@us.nestle.com
Reviewers
NAME	ROLE	CONTACT NUMBER
Vimaljith	Wipro SME	vimaljith.johny@nestle.com
Phani D	Nestle Product Owner	phani.daliparthi@us.nestle.com

Document History
Date	Name	Changes		Version
31/3/2026	Monse Raj	Inception	Draft 1.0












Overview:
 This document outlines the changes needed in the exi
sting vnet expansion automation logic to absorb the inclusion of SDWAN Edge router in AMS , EUR and AOA region.

 Details:
PROD Vnets:
When a PROD (hub vnet or spoke vnet) vnet expansion happens then Route Table of the vrf1data needs to be updated, As per the current vnet expansion automation logic, vrf1data RT will be updated, since the vrf1data RT is residing in the PROD HUB network RG.
 
But as per the current logic of vnet expansion automation, new address space of the prod vnet will be updated in other RouteTables of the SDWAN router such as vrf1otherdata, vrf2 guest, vrf11mgmt ....etc. We should intentionally avoid the UDR(user defined Route) updation in the Route Table associated with the vrf1otherdata subnet.
<<Route table name is shared later in this document>>

Non PROD Vnets:
 Similarly, When a  Non PROD(hub vnet or spoke vnet ) vnet expansion happens then RouteTable of the vrf1otherdata needs to be updated, which resides in the PROD Network Hub RG,  As per the current vnet expansion automation logic, it will not update any  RouteTable resides in the prod environment.(it will update only in the Non Prod because we are expansion the address space in a Non prod Vnet).  So vnet expansion logic needs to be modified  to update only the vrf1otherdata RT resides in the Prod HUB Network RG when some Non prod Vnet expansion happens.
<<Route table name is shared later in this document>>
 
When it comes to DC Ext, there is no automation for vnet expansion, In that case we need to update the vrf1data RT manually. This UDR updation for the DC ext is out of scope of the automation team.
 
Similarly, for the vnet expansion of the W2K DC EXT, W2K IT HUB, RTE DC ext , we need to manually update the RT of the Vrf1 otherdata. Again, this UDR updation for the  W2K DC EXT, W2K IT HUB, RTE DC ext environments are out of scope of the automation team.
 


Automation use case that needs modification: Vnet expansion.


 
AMS Region:
Below are the 4 SDWAN Route Tables for the AMS region, that resides in the PROD network HUB RG
RG:
nams-pr-network-ithub-usea-001-rgp
Route Tables:
nams-pr-ccn.vrf111mgmt-usea-001-rtb
nams-pr-ccn.vrf1data-usea-001-rtb
nams-pr-ccn.vrf1otherdata-usea-001-rtb
nams-pr-ccn.vrf2guest-usea-001-rtb
 
When an AMS Prod vnet expansion happens, among the above 4 Route Tables, UDR updation should NOT happen on the Route Table - nams-pr-ccn.vrf1otherdata-usea-001-rtb.
Rest all route tables will be updated as per the current automation logic.
 
When an AMS Non Prod vnet expansion happens, among the above 4 Route Tables, UDR updation should happen on the Route Table - nams-pr-ccn.vrf1otherdata-usea-001-rtb.
Rest all route table will not be updated as per the current automation logic



EUR Region:
 
Below are the 4 SDWAN Route Tables for the EUR region, that resides in the  PROD network HUB RG
 RG:
emna-pr-network-ithub-euwe-001-rgp
Route Table:
emna-pr-ccn.vrf111mgmt-euwe-001-rtb
emna-pr-ccn.vrf1data-euwe-001-rtb
emna-pr-ccn.vrf1otherdata-euwe-001-rtb
emna-pr-ccn.vrf2guest-euwe-001-rtb
 
When an EUR Prod vnet expansion happens, among the above 4 Route Tables, UDR updation should NOT happen on the Route Table - emna-pr-ccn.vrf1otherdata-euwe-001-rtb.
Rest all route tables will be updated as per the current automation logic.
 
When an EUR Non Prod vnet expansion happens, among the above 4 Route Tables, UDR updation should happen on the Route Table - emna-pr-ccn.vrf1otherdata-euwe-001-rtb.
Rest all route table will not be updated as per the current automation logic


 
AOA Region:
 
Below are the 4 SDWAN Route Tables for the EUR region, that resides in the  PROD network HUB RG
 
RG:
naoa-pr-network-ithub-asse-001-rgp
Route Table:
naoa-pr-ccn.vrf111mgmt-asse-001-rtb
naoa-pr-ccn.vrf1data-asse-001-rtb
naoa-pr-ccn.vrf1otherdata-asse-001-rtb
naoa-pr-ccn.vrf2guest-asse-001-rtb
 
When an AOA Prod vnet expansion happens, among the above 4 Route Tables, UDR updation should NOT happen on the Route Table - naoa-pr-ccn.vrf1otherdata-asse-001-rtb.
Rest all route tables will be updated as per the current automation logic.
 
When an AOA  Non Prod vnet expansion happens, among the above 4 Route Tables, UDR updation should happen on the Route Table - naoa-pr-ccn.vrf1otherdata-asse-001-rtb.
Rest all route table will not be updated as per the current automation logic


Conclusion:
By the implementation of the above enhancement in the existing vnet expansion automation usecase, our Azure environments will be updated automatically with necessary routes/UDRs in all the required Route Tables of SDWAN Edge Router along with other Route Tables in the environment.


