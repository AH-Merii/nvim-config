<!-- pydantic 2.14.1, pyrefly 1.4.0 hover, corpus pydantic__StringConstraints.md:21-28 -->
Example:  
&nbsp;&nbsp;&nbsp;&nbsp;```python  
&nbsp;&nbsp;&nbsp;&nbsp;from typing import Annotated  
  
&nbsp;&nbsp;&nbsp;&nbsp;from pydantic.types import StringConstraints  
  
&nbsp;&nbsp;&nbsp;&nbsp;ConstrainedStr = Annotated[str, StringConstraints(min_length=1, max_length=10)]  
&nbsp;&nbsp;&nbsp;&nbsp;```