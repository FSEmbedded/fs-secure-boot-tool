File:     README.txt
Author:   Patrick Jakob
Created:  31.08.2017
Modified: 31.08.2017 09:08 (PJ)
Modified: 15.01.2019 09:16 (PJ)


F&S Secure Boot Tool for F&S Bootloader & Kernel/DT
===========================================

When images must be signed/encrypted this User Tool do that. This User Tool
sign or encrypt the given image.


generate.sh
-----------
This is the main script. In this script there are 3 opportunity to choose.
Create certificates, sign images or encrypt images. If one opportunity
chosen the makeAction.sh will be called.


makeAction.sh
-------------
This script handle the given parameters and call one of the following scripts:
- createCertificates.sh
- signImage.sh
- encryptImage.sh


createCertificates.sh
---------------------
This script gets some information and call the NXP Code Signing Tool
hab4_pki_tree.sh script. This script creates the certificates. After that the
SRK_Table and the SRK_fuse will be created with the help of the NXP Code
Signing Tool srktool script.


signImage.sh
------------
This script fill the Command Sequence file and call the NXP Code Signing Tool
cst script. This script outputs a signature. The signature will be merged in
the given Image. The output is a signed Image.


encryptImage.sh
---------------
This script fill the Command Sequence file and call the NXP Code Signing Tool
cst script. This script outputs a signature and the encryption key. The
signature will be merged in the given Image. The output is a encrypted Image.


jtag.sh
-------
This script creates a JTAG response key. After that you can burn the JTAG
response key in NBoot to use secure JTAG.

