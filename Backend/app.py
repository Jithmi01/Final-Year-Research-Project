from flask import Flask
from flask_cors import CORS

def create_app():
    app = Flask(__name__)
    CORS(app)

    # Register routes
    from routes.user_routes import user
    app.register_blueprint(user)

    return app

app = create_app()

if __name__ == "__main__":
    app.run(debug=True)
