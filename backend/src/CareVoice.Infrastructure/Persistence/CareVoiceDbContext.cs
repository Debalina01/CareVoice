using Microsoft.EntityFrameworkCore;
using CareVoice.Domain.Entities;

namespace CareVoice.Infrastructure.Persistence;

public class CareVoiceDbContext : DbContext
{
    public CareVoiceDbContext(DbContextOptions<CareVoiceDbContext> options) : base(options)
    {
    }

    public DbSet<User> Users => Set<User>();
    public DbSet<FamilyMember> FamilyMembers => Set<FamilyMember>();
    public DbSet<FamilyGroup> FamilyGroups => Set<FamilyGroup>();
    public DbSet<FamilyGroupMember> FamilyGroupMembers => Set<FamilyGroupMember>();
    public DbSet<FamilyPermission> FamilyPermissions => Set<FamilyPermission>();
    public DbSet<Invite> Invites => Set<Invite>();
    public DbSet<Device> Devices => Set<Device>();
    public DbSet<Medicine> Medicines => Set<Medicine>();
    public DbSet<MedicineSchedule> MedicineSchedules => Set<MedicineSchedule>();
    public DbSet<MedicineLog> MedicineLogs => Set<MedicineLog>();
    public DbSet<Notification> Notifications => Set<Notification>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();
    public DbSet<MedicalDocument> MedicalDocuments => Set<MedicalDocument>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<User>(entity =>
        {
            entity.HasKey(u => u.Id);
            entity.HasIndex(u => u.Email).IsUnique();
            entity.Property(u => u.Email).HasMaxLength(256).IsRequired();
            entity.Property(u => u.Username).HasMaxLength(100);
            entity.Property(u => u.FullName).HasMaxLength(150).IsRequired();
        });

        modelBuilder.Entity<FamilyMember>(entity =>
        {
            entity.HasKey(fm => fm.Id);
            entity.HasOne(fm => fm.User)
                  .WithMany(u => u.FamilyMembers)
                  .HasForeignKey(fm => fm.UserId)
                  .OnDelete(DeleteBehavior.Cascade);
            entity.HasOne(fm => fm.LinkedUser)
                  .WithMany()
                  .HasForeignKey(fm => fm.LinkedUserId)
                  .IsRequired(false)
                  .OnDelete(DeleteBehavior.SetNull);
        });

        modelBuilder.Entity<FamilyGroup>(entity =>
        {
            entity.HasKey(fg => fg.Id);
            entity.HasIndex(fg => fg.FamilyCode).IsUnique();
            entity.Property(fg => fg.FamilyCode).HasMaxLength(20).IsRequired();
            entity.Property(fg => fg.Name).HasMaxLength(150).IsRequired();
            entity.HasOne(fg => fg.CreatorUser)
                  .WithMany()
                  .HasForeignKey(fg => fg.CreatorUserId)
                  .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<FamilyGroupMember>(entity =>
        {
            entity.HasKey(fgm => fgm.Id);
            entity.HasIndex(fgm => new { fgm.FamilyGroupId, fgm.UserId }).IsUnique();
            entity.HasOne(fgm => fgm.FamilyGroup)
                  .WithMany(fg => fg.Members)
                  .HasForeignKey(fgm => fgm.FamilyGroupId)
                  .OnDelete(DeleteBehavior.Cascade);
            entity.HasOne(fgm => fgm.User)
                  .WithMany(u => u.GroupMemberships)
                  .HasForeignKey(fgm => fgm.UserId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<FamilyPermission>(entity =>
        {
            entity.HasKey(fp => fp.Id);
            entity.HasOne(fp => fp.GranterMember)
                  .WithMany(fm => fm.GrantedPermissions)
                  .HasForeignKey(fp => fp.GranterMemberId)
                  .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(fp => fp.GranteeMember)
                  .WithMany(fm => fm.ReceivedPermissions)
                  .HasForeignKey(fp => fp.GranteeMemberId)
                  .OnDelete(DeleteBehavior.Restrict);

            entity.HasIndex(fp => new { fp.GranterMemberId, fp.GranteeMemberId }).IsUnique();
        });

        modelBuilder.Entity<Invite>(entity =>
        {
            entity.HasKey(i => i.Id);
            entity.HasIndex(i => i.InviteToken).IsUnique();
            entity.HasOne(i => i.InviterMember)
                  .WithMany()
                  .HasForeignKey(i => i.InviterMemberId)
                  .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<Device>(entity =>
        {
            entity.HasKey(d => d.Id);
            entity.HasOne(d => d.User)
                  .WithMany(u => u.Devices)
                  .HasForeignKey(d => d.UserId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<Medicine>(entity =>
        {
            entity.HasKey(m => m.Id);
            entity.HasOne(m => m.OwnerMember)
                  .WithMany(fm => fm.Medicines)
                  .HasForeignKey(m => m.OwnerMemberId)
                  .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<MedicineSchedule>(entity =>
        {
            entity.HasKey(ms => ms.Id);
            entity.HasOne(ms => ms.Medicine)
                  .WithMany(m => m.Schedules)
                  .HasForeignKey(ms => ms.MedicineId)
                  .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(ms => ms.TargetMember)
                  .WithMany()
                  .HasForeignKey(ms => ms.TargetMemberId)
                  .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(ms => ms.CreatedByMember)
                  .WithMany()
                  .HasForeignKey(ms => ms.CreatedByMemberId)
                  .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<MedicineLog>(entity =>
        {
            entity.HasKey(ml => ml.Id);
            entity.HasIndex(ml => ml.ClientLogId).IsUnique();
            entity.HasOne(ml => ml.Schedule)
                  .WithMany(ms => ms.Logs)
                  .HasForeignKey(ml => ml.ScheduleId)
                  .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(ml => ml.TargetMember)
                  .WithMany()
                  .HasForeignKey(ml => ml.TargetMemberId)
                  .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<Notification>(entity =>
        {
            entity.HasKey(n => n.Id);
            entity.HasOne(n => n.RecipientUser)
                  .WithMany(u => u.Notifications)
                  .HasForeignKey(n => n.RecipientUserId)
                  .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<AuditLog>(entity =>
        {
            entity.HasKey(a => a.Id);
            entity.HasIndex(a => a.Timestamp);
        });

        modelBuilder.Entity<MedicalDocument>(entity =>
        {
            entity.HasKey(md => md.Id);
            entity.HasIndex(md => md.OwnerMemberId);
            entity.HasIndex(md => md.StorageObjectKey).IsUnique();
            entity.Property(md => md.Title).HasMaxLength(200).IsRequired();
            entity.Property(md => md.Category).HasMaxLength(50).IsRequired();
            entity.Property(md => md.OriginalFileName).HasMaxLength(255).IsRequired();
            entity.Property(md => md.ContentType).HasMaxLength(150).IsRequired();
            entity.Property(md => md.StorageProvider).HasMaxLength(50).IsRequired();
            entity.Property(md => md.StorageBucket).HasMaxLength(150).IsRequired();
            entity.Property(md => md.StorageObjectKey).HasMaxLength(500).IsRequired();
            entity.Property(md => md.Sha256Hash).HasMaxLength(128).IsRequired();

            entity.HasOne(md => md.OwnerMember)
                  .WithMany(fm => fm.MedicalDocuments)
                  .HasForeignKey(md => md.OwnerMemberId)
                  .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(md => md.UploadedByUser)
                  .WithMany()
                  .HasForeignKey(md => md.UploadedByUserId)
                  .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(md => md.Medicine)
                  .WithMany()
                  .HasForeignKey(md => md.MedicineId)
                  .IsRequired(false)
                  .OnDelete(DeleteBehavior.SetNull);
        });
    }
}
