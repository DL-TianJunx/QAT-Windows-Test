## Summary of KPT20 test

This test suite is the testing `encrypt|decrypt` of the AES-GSM algorithm using `fips_windows.exe` tool.

## Before running the test suite

Prepare the test case such as ACVP-AES-GCM.req into the folder QAT-Windows-Test\FIPS. It's include input parameter : input message, key, IV, AAD, Taglen and Payloadlen.

Use the script WHost_FIPS.ps1 will write the input message, key, IV, AAD into the in.hex, key.hex, iv.hex, aad.hex file and run the test suite by using fips_windows.exe.

## Running the test suite 

### **Run single test with fips_windows.exe**

fips_windows.exe <direction> <In> <Key> <IV> <AAD> <Taglen> <Payloadlen> <Output>

**Example: **

fips_windows.exe encrypt in.hex key.hex IV.hex aad.hex 64 7264 out.hex

### Run the test suite on the local

.\WHost_FIPS.ps1 -BertaResultPath <Path of test result> -UQMode $true -RunOnLocal $true

