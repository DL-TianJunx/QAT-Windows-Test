**## How to run tests using PowerShell scripts:**

1.

Run tests using specific runner PowerShell script for specific algorithm:
    
| Python script     | Binary from build directory | Algorithm                 |
| ----------------- | --------------------------- | ------------------------- |
| runner_AES_CCM.py | fips_ccm_sample             | AES-CCM                   |
| runner_AES_GCM.py | fips_gcm_sample             | AES-GCM                   |
| runner_AES_XTS.py | fips_cipher_sample          | AES-XTS                   |
| runner_AES.py     | fips_cipher_sample          | AES-CBC, AES-ECB, AES-CTR |

2. You need to run tests using following ".\runner_AES_xxx.ps1 <app_path> <in_file_with_vectors> <output_file_with_responses>" examples:

   \- for AES-GCM:

     \```

     .\runner_AES_GCM.ps1 -app_path "D:\FIPS\fips_windows.exe" -samples_path "D:\FIPS\ACVP-AES-GCM.req" -samples_result_path "D:\FIPS\ACVP-AES-GCM.json"

     \```