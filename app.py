from flask import Flask
app = Flask(__name__)

@app.route('/')
def pretend(event,context):
    return 'Lets pretend this function eats lots of resources!'
