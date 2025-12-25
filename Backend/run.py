# FILE: run.py (ROOT LEVEL)
# Entry point for the application
# ============================================================================

"""
Smart Wallet Backend - Entry Point
Run this file to start the server: python run.py
"""

from main import app
from config.settings import API_HOST, API_PORT, DEBUG

if __name__ == "__main__":
    print("=" * 80)
    print("  🚀 SMART WALLET BACKEND API")
    print("=" * 80)
    print(f"  Server: http://{API_HOST}:{API_PORT}")
    print(f"  Debug Mode: {DEBUG}")
    print("=" * 80)
    print()
    
    app.run(host=API_HOST, port=API_PORT, debug=DEBUG)