#!/usr/bin/env python3
"""
Demo of the new replication monitoring feature
"""

import time
import random

def demonstrate_replication_monitoring():
    print("=== New Replication Monitoring Feature - End of Phase 2 ===\n")
    
    print("🚀 After SVM peering setup completes, users will see:")
    print("  ")
    print("  💡 Important notes:")
    print("    • Do NOT break replication until you're ready to switch to the Azure volume")
    print("    • Breaking replication makes the Azure volume writable but stops sync from on-premises")
    print("    • Plan your cutover carefully to minimize downtime")
    print("  ")
    print("  Would you like to monitor the replication status now? (Shows transfer progress and speed) [y/N]: y")
    print("  ")
    
    print("📊 Replication Status Monitor")
    print("═" * 50)
    print("ℹ️  Starting real-time replication monitoring for volume: fujipacstst")
    print("")
    print("📊 Note: Azure metrics typically have a 5-minute delay in updates")
    print("ℹ️  Monitoring will refresh every 60 seconds")
    print("ℹ️  Press Ctrl+C at any time to stop monitoring and continue")
    print("")
    
    # Simulate monitoring output
    start_gb = 2.1
    start_time = time.time()
    
    for check in range(1, 6):
        current_time_str = time.strftime('%H:%M:%S')
        print(f"🔍 Replication Check {check}/30 - {current_time_str}")
        
        # Simulate realistic transfer progression
        elapsed_minutes = check - 1
        if check == 1:
            # First measurement - baseline
            transferred_gb = start_gb
            progress_gb = start_gb * 0.95
            print(f"📊 Total Transferred: {transferred_gb:.2f} GB")
            print(f"📈 Progress: {progress_gb:.2f} GB")
            print(f"🕒 Last Update: 2025-09-25T{current_time_str}Z")
            print("🏁 Baseline established: Starting average rate calculation")
        else:
            # Simulate steady transfer rate of ~15 Mbps (1.875 MB/s, ~112.5 MB/min, ~0.11 GB/min)
            additional_transfer = elapsed_minutes * 0.11
            transferred_gb = start_gb + additional_transfer + random.uniform(-0.05, 0.05)
            progress_gb = transferred_gb * 0.95 + random.uniform(-0.02, 0.02)
            
            print(f"📊 Total Transferred: {transferred_gb:.2f} GB")
            print(f"📈 Progress: {progress_gb:.2f} GB")
            print(f"🕒 Last Update: 2025-09-25T{current_time_str}Z")
            
            # Calculate average rate since start
            total_transferred = transferred_gb - start_gb
            elapsed_seconds = elapsed_minutes * 60
            if elapsed_seconds > 0 and total_transferred > 0:
                avg_mb_per_sec = (total_transferred * 1024) / elapsed_seconds  # GB to MB, divided by seconds
                avg_mbps = avg_mb_per_sec * 8
                
                # Format elapsed time
                if elapsed_minutes >= 60:
                    hours = elapsed_minutes // 60
                    minutes = elapsed_minutes % 60
                    elapsed_str = f"{hours}h {minutes}m"
                else:
                    elapsed_str = f"{elapsed_minutes}m"
                
                print(f"🚀 Average Transfer Rate: {avg_mb_per_sec:.2f} MB/s ({avg_mbps:.2f} Mbps)")
                print(f"📈 Total Progress: {total_transferred:.2f} GB in {elapsed_str}")
        
        print("")
        
        if check < 5:
            print("⏳ Next check in 60 seconds... (Press Ctrl+C to stop monitoring)")
            print("")
            time.sleep(1)  # Short delay for demo
    
    print("✅ Replication monitoring completed")
    print("💡 You can continue monitoring in the Azure Portal or restart this monitor anytime")
    print("")
    print("✅ Setup phase completed successfully!")
    print("📝 Detailed logs are available in: anf_migration_interactive.log")
    
    print(f"\n💡 Key Features:")
    print("  • Real-time transfer progress in GB/TB")
    print("  • Average transfer rate since monitoring started (not just last interval)")
    print("  • Shows total progress with elapsed time")
    print("  • Azure metrics delay warning (5-minute delay)")
    print("  • 1-minute refresh intervals")
    print("  • Interruptible with Ctrl+C")
    print("  • Optional - users can skip and check Azure Portal instead")
    print("  • Shows both total transferred and current progress")
    print("  • Baseline establishment for accurate average calculations")
    print("  • Handles metrics parsing errors gracefully")

if __name__ == "__main__":
    demonstrate_replication_monitoring()