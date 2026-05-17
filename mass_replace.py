import os

replacements = [
    ("AI Coaching", "Cricknova Chat Coach"),
    ("AI Chat Coach", "Cricknova Chat Coach"),
    ("AI Coach", "Cricknova Chat Coach"),
    ("AI Chats", "Cricknova Chat Coach"),
    ("AI Cricket Chats", "Cricknova Chat Coach"),
    ("AI Mistake Detection", "Cricknova Mistake Detection"),
    ("Mistake Detection", "Cricknova Mistake Detection"),
    ("Bowling Cricknova Mistake Detection", "Cricknova Mistake Detection"),
    ("Cricknova Cricknova Mistake Detection", "Cricknova Mistake Detection"),
    ("Cricknova Cricknova Chat Coach", "Cricknova Chat Coach"),
    ("Analyse Yourself Batting/Bowling (60 Vid Compare)", "60 Cricknova Analyse Yourself"),
    ("Analyse Yourself Batting/Bowling (150 Vid Compare)", "150 Cricknova Analyse Yourself"),
    ("Analyse Yourself Batting/Bowling", "Cricknova Analyse Yourself"),
    ("Analyse Yourself", "Cricknova Analyse Yourself"),
    ("Cricknova Cricknova Analyse Yourself", "Cricknova Analyse Yourself"),
]

for root, _, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r') as f:
                content = f.read()
            
            new_content = content
            for old, new in replacements:
                new_content = new_content.replace(old, new)
            
            if new_content != content:
                with open(filepath, 'w') as f:
                    f.write(new_content)
                print(f"Updated {filepath}")
