"""Pydantic models for request/response schemas."""

from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel, Field


class AppleAuthRequest(BaseModel):
    """Request body for /auth/apple endpoint."""
    identity_token: str = Field(..., description="JWT identity token from Apple")
    authorization_code: str = Field(..., description="Authorization code from Apple")


class User(BaseModel):
    """User information."""
    user_id: str = Field(..., description="Identity Platform user ID")
    email: Optional[str] = Field(None, description="User email address")
    display_name: Optional[str] = Field(None, description="User display name")
    created_at: Optional[datetime] = Field(None, description="User creation timestamp")


class AuthResponse(BaseModel):
    """Response from /auth/apple endpoint."""
    id_token: str = Field(..., description="Identity Platform ID token")
    refresh_token: Optional[str] = Field(None, description="Refresh token (if available)")
    expires_in: int = Field(..., description="Token expiration time in seconds")
    user: User = Field(..., description="User information")


# Health data models matching iOS HealthDataBatch structure
class QuantitySample(BaseModel):
    """A quantity sample from HealthKit."""
    type: str
    value: float
    unit: str
    startDate: datetime
    endDate: datetime
    sourceName: str
    sourceBundle: str


class SleepSample(BaseModel):
    """A sleep sample from HealthKit."""
    stage: str
    startDate: datetime
    endDate: datetime
    sourceName: str


class WorkoutSample(BaseModel):
    """A workout sample from HealthKit."""
    activityType: str
    duration: float
    totalEnergyBurned: Optional[float] = None
    totalDistance: Optional[float] = None
    startDate: datetime
    endDate: datetime
    sourceName: str


class HealthDataBatch(BaseModel):
    """Health data batch from iOS app."""
    heartRate: List[QuantitySample] = Field(default_factory=list)
    hrv: List[QuantitySample] = Field(default_factory=list)
    restingHeartRate: List[QuantitySample] = Field(default_factory=list)
    walkingHeartRateAverage: List[QuantitySample] = Field(default_factory=list)
    respiratoryRate: List[QuantitySample] = Field(default_factory=list)
    oxygenSaturation: List[QuantitySample] = Field(default_factory=list)
    vo2Max: List[QuantitySample] = Field(default_factory=list)
    steps: List[QuantitySample] = Field(default_factory=list)
    activeEnergy: List[QuantitySample] = Field(default_factory=list)
    exerciseTime: List[QuantitySample] = Field(default_factory=list)
    standTime: List[QuantitySample] = Field(default_factory=list)
    timeInDaylight: List[QuantitySample] = Field(default_factory=list)
    bodyMass: List[QuantitySample] = Field(default_factory=list)
    bodyFatPercentage: List[QuantitySample] = Field(default_factory=list)
    leanBodyMass: List[QuantitySample] = Field(default_factory=list)
    sleep: List[SleepSample] = Field(default_factory=list)
    workouts: List[WorkoutSample] = Field(default_factory=list)
    fetchedAt: datetime


class WatchEventsResponse(BaseModel):
    """Response from /watch_events endpoint."""
    message: str
    samples_received: int
    user_id: str


