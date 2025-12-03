# Azure NetApp Files Migration - Best Practices Guide

## Overview

This guide provides best practices and recommendations for successfully migrating on-premises NetApp volumes to Azure NetApp Files using the Migration Assistant PowerShell tool.

## Pre-Migration Planning

### 1. Assess Your Environment

**Source System Assessment:**
- Document current volume size and growth rate
- Identify peak usage times
- Review access patterns (NFS/SMB, read/write ratios)
- Note any special configurations (snapshots, quotas, QoS)

**Network Planning:**
- Verify network bandwidth between on-premises and Azure
- Calculate expected sync time based on volume size and bandwidth
- Plan for dedicated circuits if needed (ExpressRoute recommended)

**Capacity Planning:**
- Choose appropriate service level (Standard/Premium/Ultra)
- Size capacity pool with headroom (recommend 20% over volume size)
- Consider future growth when sizing

### 2. Create a Migration Schedule

**Recommended Timeline:**

| Phase | Duration | Activities |
|-------|----------|------------|
| **Planning** | 1-2 weeks | Assessment, network setup, Azure resource creation |
| **Setup** | 1 day | Run setup wizard, configure parameters |
| **Peering** | 2-4 hours | Execute peering workflow, verify connectivity |
| **Initial Sync** | Hours to days | Wait for first data sync to complete |
| **Delta Syncs** | Ongoing | Monitor periodic synchronization |
| **Cutover** | 1-4 hours | Final sync, break replication, switch clients |
| **Validation** | 1-2 days | Verify data, test applications, monitor performance |

## Migration Workflow

### Phase 1: Azure Resource Preparation

**Before running the script, create:**

1. **Resource Group**
   ```powershell
   New-AzResourceGroup -Name "rg-anf-migration" -Location "eastus"
   ```

2. **Virtual Network with Delegated Subnet**
   - Create VNet with address space (e.g., 10.0.0.0/16)
   - Create subnet for ANF (e.g., 10.0.1.0/24)
   - Delegate subnet to Microsoft.NetApp/volumes

3. **Azure NetApp Files Account**
   - Create through Azure Portal or CLI
   - Note the account name for configuration

4. **Capacity Pool**
   - Choose service level based on performance needs
   - Size appropriately for your volume(s)

### Phase 2: Configuration

Run the setup wizard:

```powershell
.\anf_interactive.ps1 setup
```

**Configuration Tips:**
- Use descriptive volume names that indicate migration (e.g., `prod-data-migrated`)
- Keep replication schedule as `hourly` for most scenarios
- For large volumes (>50TB), enable large volume support
- Use Standard network features unless you need advanced networking

### Phase 3: Peering and Initial Sync

Execute the peering workflow:

```powershell
.\anf_interactive.ps1 peering
```

**What to Expect:**

1. **Volume Creation** (5-10 minutes)
   - Azure creates the target volume
   - Volume is initially in DP (Data Protection) mode

2. **Cluster Peering** (5-15 minutes)
   - Script provides ONTAP command to run
   - Execute command on your ONTAP system
   - Enter passphrase when prompted

3. **SVM Peering** (5-10 minutes)
   - Script provides ONTAP command to run
   - Execute command to establish SVM relationship
   - Data sync begins automatically

**Best Practices:**
- Have ONTAP admin credentials ready
- Keep the PowerShell window open while executing ONTAP commands
- Copy/paste commands exactly as provided
- Document the passphrase for troubleshooting

### Phase 4: Monitoring Initial Sync

**Monitor in Azure Portal:**
1. Navigate to your volume → Metrics
2. Key metrics to watch:
   - **Volume Replication Total Transfer** - Shows total data transferred
   - **Volume Replication Last Transfer Size** - Shows recent sync size
   - **Volume Replication Lag Time** - Should decrease over time

**Use the monitoring command:**
```powershell
.\anf_interactive.ps1 monitor
```

**Initial Sync Timeline Estimates:**

| Volume Size | Expected Duration |
|-------------|-------------------|
| 100 GB | 1-2 hours |
| 1 TB | 6-12 hours |
| 10 TB | 2-4 days |
| 50 TB | 1-2 weeks |

*Note: Times vary based on network bandwidth and change rate*

### Phase 5: Delta Synchronization

**During this phase:**
- Data continues syncing on schedule (hourly by default)
- Only changed data is transferred
- Volume remains in DP mode (read-only)
- Monitor lag time to ensure sync keeps up with changes

**When to Move to Cutover:**
- Replication lag time is minimal (< 1 hour)
- Delta sync completes quickly (< 30 minutes)
- Business is ready for cutover window

### Phase 6: Cutover Planning

**Pre-Cutover Checklist:**

- [ ] Verify all data is synced (check metrics)
- [ ] Schedule maintenance window
- [ ] Notify users of impending change
- [ ] Prepare rollback plan
- [ ] Document current source volume mount points
- [ ] Test connectivity from clients to Azure
- [ ] Have ONTAP and Azure admin access ready

**Recommended Cutover Steps:**

1. **Reduce Change Rate** (1-2 hours before)
   - Stop non-essential write activity
   - Pause batch jobs if possible

2. **Perform Pre-Cutover Sync**
   - Manually trigger SnapMirror update on ONTAP if needed
   - Monitor until sync completes

3. **Stop Source Access** (beginning of maintenance window)
   - Unmount source volume from all clients
   - Disable write access

4. **Execute Break Replication**
   ```powershell
   .\anf_interactive.ps1 break
   ```

5. **Verify Volume is Writable**
   - Check volume status in Azure Portal
   - Mount point information is displayed after break

6. **Update Client Configurations**
   - Update mount points to Azure NetApp Files
   - Test application connectivity
   - Verify read/write operations

7. **Monitor Performance**
   - Watch for any latency issues
   - Check application logs
   - Verify user access

### Phase 7: Post-Migration

**Immediate Actions (First 24 hours):**
- Monitor volume performance and capacity
- Check application functionality
- Verify backup systems are configured
- Document any issues

**First Week:**
- Review performance metrics daily
- Validate data integrity
- Confirm all users can access
- Update documentation

**First Month:**
- Establish baseline performance metrics
- Review and optimize if needed
- Consider snapshot policies
- Plan for eventual decommission of source volume

## Troubleshooting Common Issues

### Slow Initial Sync

**Symptoms:** Initial sync taking much longer than expected

**Solutions:**
- Check network bandwidth utilization
- Verify no QoS limits on source or network
- Consider ExpressRoute for large volumes
- Check for high change rate on source

### Replication Lag Increasing

**Symptoms:** Lag time keeps growing, sync never catches up

**Solutions:**
- Increase network bandwidth
- Reduce change rate on source if possible
- Check for network issues or packet loss
- Verify service level is appropriate for workload

### "Cannot Start Transfer - Transfer in Progress"

**Symptoms:** Break replication fails with this error

**Solutions:**
- Wait for current transfer to complete
- Script automatically waits up to 30 minutes
- Check Azure Portal for transfer status
- If persistent, contact Azure support

### Volume Not Writable After Break

**Symptoms:** Volume shows as DP mode after break operation

**Solutions:**
- Check if break operation completed successfully
- Run break operation again
- Verify in Azure Portal that finalize completed
- Contact Azure support if issue persists

## Performance Optimization

### Choosing the Right Service Level

| Service Level | Throughput | Best For |
|---------------|------------|----------|
| **Standard** | Up to 16 MiB/s per TB | File shares, dev/test, archives |
| **Premium** | Up to 64 MiB/s per TB | Business apps, databases |
| **Ultra** | Up to 128 MiB/s per TB | HPC, latency-sensitive workloads |

### Network Features

- **Standard**: Default, suitable for most workloads
- **Basic**: Legacy, not recommended for new deployments

### Large Volume Support

Enable for volumes > 50 TB:
```json
{
  "target_is_large_volume": "true"
}
```

## Security Best Practices

1. **Service Principal Management**
   - Use dedicated service principal for migration
   - Rotate secrets regularly
   - Remove permissions after migration completes

2. **Network Security**
   - Use private endpoints where possible
   - Configure NSGs to restrict access
   - Consider ExpressRoute for sensitive data

3. **Data Protection**
   - Enable snapshot policies post-migration
   - Configure backup if required
   - Test restore procedures

## Cost Optimization

1. **Right-Size from Start**
   - Don't over-provision capacity
   - Start with Standard, upgrade if needed

2. **Clean Up**
   - Delete source volume after validation period
   - Remove unused capacity pools
   - Clean up test resources

3. **Monitor Usage**
   - Review capacity utilization monthly
   - Adjust service level based on actual performance needs

## Support and Resources

- **Azure NetApp Files Documentation**: https://docs.microsoft.com/azure/azure-netapp-files/
- **Azure Support**: Create ticket through Azure Portal
- **Script Issues**: Check log file `anf_migration_interactive.log`

---

*For detailed command reference, see [README.md](README.md).*
