class ValidationError(Exception):
    def __init__(self, message):
        self.message = message
def validate(instance, schema):
    # Mock validation: always pass unless schema is explicitly "FAIL"
    if schema == "FAIL":
        raise ValidationError("Mock validation failed")
    return True
