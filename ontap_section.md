---

## ONTAP Volume Identification and Cluster Information Collection Guide

### Purpose

This guide walks administrators through identifying a specific volume on an ONTAP cluster and gathering key information for troubleshooting, migration, or reporting.

The process collects the following values:
- **Cluster Name**
- **Host (Node) Name**
- **SVM Name**
- **LIF IP Addresses**

---

### 1. Log in to the Cluster

Use SSH or console access to connect to your cluster management interface:

```bash
ssh admin@<cluster-mgmt-IP>
```

You should see a prompt similar to:

```text
CLUSTERNAME::>
```

If you see a prompt with only a single `>`, type:

```bash
cluster shell
```

to enter the cluster-level shell.

---

### 2. Find the Volume You're Looking For

List all volumes in the cluster and locate the one you're interested in:

```bash
volume show -fields volume
```

**Example output:**

```text
vserver       volume
------------- -------------
SNCMK         vol0
TEST_API_SVM  nfsdata01
TEST_API_SVM  fslogix_user01
```

✅ Note the **volume name** (e.g. `fslogix_user01`) and its **SVM name** (e.g. `TEST_API_SVM`).

---

### 3. Collect the Cluster, Host, SVM, and LIF Information

Once you know the SVM name, run the following commands to collect all relevant details.

#### 3.1 Get the Cluster Name

```bash
cluster identity show -fields cluster-name
```

**Example output:**

```text
cluster-name: SNCMK
```

---

#### 3.2 Get the Host (Node) Name

```bash
system node show -fields node
```

**Example output:**

```text
node: SNCMK-01
```

---

#### 3.3 Confirm the SVM Name for Your Volume

Use the volume name you identified earlier:

```bash
volume show -volume fslogix_user01 -fields vserver
```

**Example output:**

```text
vserver: TEST_API_SVM
```

---

#### 3.4 Get the LIF IPs for the SVM

```bash
network interface show -vserver TEST_API_SVM -fields address
```

**Example output:**

```text
vserver      lif                 address
------------ ------------------- -------------
TEST_API_SVM TEST_API_SVM_data_1 10.199.6.56
TEST_API_SVM TEST_API_SVM_iscsi_1 10.199.6.55
```

---

### 4. Record Your Results

After running the four commands, record the following values:

| Field                | Example Value            |
| -------------------- | ------------------------ |
| **Cluster Name**     | SNCMK                    |
| **Host (Node) Name** | SNCMK-01                 |
| **SVM Name**         | TEST_API_SVM             |
| **LIF IPs**          | 10.199.6.56, 10.199.6.55 |

You can store this information in your tracking spreadsheet, ticket, or migration worksheet.

---

### 5. Quick Reference

| Purpose             | Command                                                 |
| ------------------- | ------------------------------------------------------- |
| List all volumes    | `volume show -fields volume`                            |
| Get cluster name    | `cluster identity show -fields cluster-name`            |
| Get host name       | `system node show -fields node`                         |
| Get SVM for volume  | `volume show -volume <volname> -fields vserver`         |
| Get LIF IPs for SVM | `network interface show -vserver <SVM> -fields address` |

---

### Example Collected Output

```text
CLUSTERNAME: SNCMK
HOSTNAME: SNCMK-01
SVM NAME: TEST_API_SVM
LIF IPs: 10.199.6.56, 10.199.6.55
```

---

### Notes

- These commands require **admin privilege level**.
- Replace `fslogix_user01` and `TEST_API_SVM` with your actual volume and SVM names.
- The guide is compatible with **ONTAP 9.7 and newer**.