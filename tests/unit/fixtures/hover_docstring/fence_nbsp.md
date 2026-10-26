<!-- fastapi 0.162.0, pyrefly 1.4.0 hover, corpus fastapi__FastAPI.get.md:33-43 -->
## Example  
  
```python  
from fastapi import FastAPI  
  
app = FastAPI()  
  
@app.get("/items/")  
def read_items():  
&nbsp;&nbsp;&nbsp;&nbsp;return [{"name": "Empanada"}, {"name": "Arepa"}]  
```