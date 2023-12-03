# Summary of KPT20 test
This test suite is the testing encrypt and decrypt or signature and verify using `kpt_tool.exe` tool.
And support generate wpk file.
This kpt tool base on the QAT windows driver.


# Before running the test suite
## Ready to the QAT windows driver
#### Driver config file: `pfvf_build.txt`
```shell
PF QAT2.0.W.2.0.0-00538
VF QAT2.0.W.2.0.0-00538
```
or
```shell
PF PF-driver-path\\QAT2.0.W.2.0.0-00538
VF VF-driver-path\\QAT2.0.W.2.0.0-00538
```
#### Driver `PDB` files: `CfQat.pdb` and `icp_qat4.pdb` and `CpmProvUser.pdb`
#### Driver certificate: `qat_cert.cer`
#### Driver `zip` file: `QAT2.0.W.2.x.x-xxxxx.zip`
#### Install the Qat windows driver on the local host or hyper-v VMs.


## Generate the wpk file
Can using `kpt_tool` generate the wpk file.
And those files(cpl.bin and swk_in.bin and iv_in.bin) are binary files.

```sh
.\kpt_tool.exe `
    -act gen `
    -in <cpk.bin> `
    -out <wpk.pem> `
    -swk <swk_in.bin> `
    -iv <iv_in.bin>
```

```shell
-in        User private key file, indicate the input path with gen action.
-out       User warpped private key file, indicate the output path with gen action.
-swk       User swk file, indicate the swk input path with gen action. It should be bin file.
-iv        User iv file, indicate the iv input path with gen action. It should be bin file.
```


# Running the test suite
## Encrypt and decrypt
Using the `wpk` file, will do encrypt and decrypt operation.
This operation just support the `rsa` algorithm.

#### Command
```sh
.\kpt_tool.exe `
    -act crypto `
    -alg rsa `
    -in <wpk.pem> `
    -payload <digest.bin>
```

```shell
-in        User warpped private key file, indicate the input path with crypto action.
-payload   User plaintext file, indicate the plain text path with crypto action. It should be bin file.
```
#### Plan of test cases
With the `rsa` algorithm, will test input and payload files:
```shell
    input file:
        -length: 512, 1024, 2048, 4096 and 8192 bits.
        -type: prime256, secp384r1 and secp521r1.
    payload file:
        -length: digest256, digest384, digest521, digest576.
        -typs: 32 and 64 bytes.
```


## Signature and verify
Using the `wpk` file, will do signature and verify operation.
This operation support the `rsa` and `ecdsa` algorithm.

#### Command
```sh
.\kpt_tool.exe `
    -act sign `
    -alg <rsa|ecdsa> `
    -in <wpk.pem> `
    -payload <digest.bin>
```

```shell
-in        User warpped private key file, indicate the input path with sign action.
-payload   User plaintext file, indicate the plain text path with sign action. It should be bin file.
```
#### Plan of test cases
With the `rsa` and `ecdsa` algorithm, will test input and payload files:
```shell
    input file:
        -length: 512, 1024, 2048, 4096 and 8192 bits.
        -type: prime256, secp384r1 and secp521r1.
    payload file:
        -length: digest256, digest384, digest521, digest576.
        -typs: 32 and 64 bytes.
```
