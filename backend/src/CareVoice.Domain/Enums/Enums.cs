namespace CareVoice.Domain.Enums;

public enum FoodRelation
{
    NoRelation = 0,
    BeforeFood = 1,
    AfterFood = 2,
    WithFood = 3
}

public enum InviteStatus
{
    Pending = 0,
    Accepted = 1,
    Rejected = 2,
    Expired = 3
}

public enum LogStatus
{
    Taken = 0,
    Skipped = 1,
    Snoozed = 2,
    Missed = 3
}

public enum DevicePlatform
{
    Android = 0,
    iOS = 1,
    Web = 2
}
