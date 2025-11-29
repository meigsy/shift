"""In-memory user repository (stub for future database)."""

from datetime import datetime
from typing import Optional, Dict
from schemas import User


class UsersRepository:
    """In-memory user storage. Designed to be swapped for database later."""
    
    def __init__(self):
        self._users: Dict[str, User] = {}
    
    def upsert_user(
        self,
        user_id: str,
        email: Optional[str] = None,
        display_name: Optional[str] = None
    ) -> User:
        """Create or update a user."""
        if user_id in self._users:
            # Update existing user
            user = self._users[user_id]
            if email is not None:
                user.email = email
            if display_name is not None:
                user.display_name = display_name
        else:
            # Create new user
            user = User(
                user_id=user_id,
                email=email,
                display_name=display_name,
                created_at=datetime.utcnow()
            )
            self._users[user_id] = user
        
        return user
    
    def get_user(self, user_id: str) -> Optional[User]:
        """Get a user by ID."""
        return self._users.get(user_id)
    
    def user_exists(self, user_id: str) -> bool:
        """Check if a user exists."""
        return user_id in self._users


# Global instance
users_repo = UsersRepository()


