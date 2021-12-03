#include <cuda_hip_wrapper.h>
#include <pybind11/pybind11.h>

#include <set>

#define FOLD_EXPRESSION(...) \
    ::consume_parameters(::std::initializer_list<int>{(__VA_ARGS__, 0)...})

// TODO: these are from the PyKokkos source code -- and they need to be
// documented

#define GET_FIRST_STRING(...)                             \
    static std::string _value = []() {                    \
        return std::get<0>(std::make_tuple(__VA_ARGS__)); \
    }();                                                  \
    return _value

#define GET_STRING_SET(...)                                    \
    static auto _value = []() {                                \
        auto _ret = std::set<std::string>{};                   \
        for (auto itr : std::set<std::string>{__VA_ARGS__}) {  \
            if (!itr.empty()) {                                \
            _ret.insert(itr);                                  \
            }                                                  \
        }                                                      \
        return _ret;                                           \
    }();                                                       \
    return _value

#define DATA_TYPE(TYPE, ENUM_ID, ...)                                 \
    template <>                                                       \
    struct DataTypeSpecialization<ENUM_ID> {                          \
        using type = TYPE;                                            \
        static std::string label() { GET_FIRST_STRING(__VA_ARGS__); } \
        static const auto& labels() { GET_STRING_SET(__VA_ARGS__); }  \
    };

namespace py = pybind11;

template <typename... Args>
void consume_parameters(Args &&...) {}

template <class T> class ptr_wrapper {
    public:
        ptr_wrapper() : ptr(nullptr) {}
        ptr_wrapper(T * ptr) : ptr(ptr) {}
        ptr_wrapper(const ptr_wrapper& other) : ptr(other.ptr) {}
        T & operator* () const { return * ptr; }
        T * operator->() const { return   ptr; }
        T * get() const { return ptr; }
        void destroy() { delete ptr; }
        ~ptr_wrapper() { delete ptr; }
        T& operator[](std::size_t idx) const { return ptr[idx]; }
    private:
        T * ptr;
};


enum DataType {
    Int16 = 0,
    Int32 = 1,
    Int64 = 2,
    UInt16 = 3,
    UInt32 = 4,
    UInt64 = 5,
    Float32= 6,
    Float64= 7,
    DataTypesEnd = 8
};


template <size_t data_type>
struct DataTypeSpecialization;


//----------------------------------------------------------------------------//
// <data-type> <enum> <string identifiers>
//  the first string identifier is the "canonical name" (i.e. what gets encoded)
//  and the remaining string entries are used to generate aliases
//
DATA_TYPE(int16_t, Int16, "int16", "short")
DATA_TYPE(int32_t, Int32, "int32", "int")
DATA_TYPE(int64_t, Int64, "int64", "long")
DATA_TYPE(uint16_t, UInt16, "uint16", "unsigned_short")
DATA_TYPE(uint32_t, UInt32, "uint32", "unsigned", "unsigned_int")
DATA_TYPE(uint64_t, UInt64, "uint64", "unsigned_long")
DATA_TYPE(float, Float32, "float32", "float")
DATA_TYPE(double, Float64, "float64", "double")


template <template <size_t> class SpecT, typename Tp, size_t ... Idx>
void generate_enumeration(
        py::enum_<Tp> & _enum, std::index_sequence<Idx...>
    ) {
        auto _generate = [& _enum](const auto & _labels, Tp _idx) {
            for (const auto & itr : _labels) {
                assert(!itr.empty());
                _enum.value(itr.c_str(), _idx);
            }
        };

        FOLD_EXPRESSION(_generate(SpecT<Idx>::labels(), static_cast<Tp>(Idx)));
}


void generate_enumeration(py::module & _mod) {
    py::enum_<DataType> _dtype(_mod, "dtype", "Raw data types");
    _dtype.export_values();
    generate_enumeration<DataTypeSpecialization>(
        _dtype,
        std::make_index_sequence<DataTypesEnd>{}
    );
}



PYBIND11_MODULE(backend, m) {
    generate_enumeration(m);

    // TODO: this is a clumsy way to define data types -- clean this up a wee
    // bit in the future.
    py::class_<ptr_wrapper<int>>(m, "Int_t");

    m.def(
        "NewInt_t",
        []() {return ptr_wrapper<int>(new int); }
    );

    py::class_<ptr_wrapper<float>>(m, "Float_t");

    m.def(
        "NewFloat_t",
        []() {return ptr_wrapper<float>(new float); }
    );

    py::class_<ptr_wrapper<cudaEvent_t>>(m, "cudaEvent_t");

    m.def(
        "NewCudaEvent_t",
        []() {return ptr_wrapper<cudaEvent_t>(new cudaEvent_t); }
    );

    py::class_<ptr_wrapper<cudaStream_t>>(m, "cudaStream_t");

    m.def(
        "NewCudaStream_t",
        []() {return ptr_wrapper<cudaStream_t>(new cudaStream_t); }
    );

    py::class_<ptr_wrapper<int *>>(m, "IntPtr_t");

    m.def(
        "NewIntPtr_t",
        []() {return ptr_wrapper<int *>(new int *); }
    );

    py::class_<ptr_wrapper<double *>>(m, "DoublePtr_t");

    m.def(
        "NewDoublePtr_t",
        []() {return ptr_wrapper<double *>(new double *); }
    );




    m.def(
        "cudaDeviceReset",
        []() {
            // TODO: use custom type for cudaError_t
            return (int64_t) cudaDeviceReset();
        }
    );


    m.def(
        "cudaDeviceSynchronize",
        []() {
            // TODO: use custom type for cudaError_t
            return (int64_t) cudaDeviceSynchronize();
        }
    );


    m.def(
        "cudaEventCreate",
        [](ptr_wrapper<cudaEvent_t> event, unsigned int flags) {
            // TODO: use custom type for cudaError_t
            return (int64_t) cudaEventCreate(event.get(), flags);
        }
    );


    m.def(
        "cudaEventElapsedTime",
        [](
            ptr_wrapper<float> ms,
            ptr_wrapper<cudaEvent_t> start,
            ptr_wrapper<cudaEvent_t> end
        ) {
            // TODO: use custom type for cudaError_t
            return (int64_t) cudaEventElapsedTime(ms.get(), * start, * end);
        }
    );


    m.def(
        "cudaEventRecord",
        [](
            ptr_wrapper<cudaEvent_t> event,
            ptr_wrapper<cudaStream_t> end = 0
        ) {
            // TODO: use custom type for cudaError_t
            return (int64_t) cudaEventRecord(* event, * end);
        }
    );


    m.def(
        "cudaEventSynchronize",
        [](ptr_wrapper<cudaEvent_t> event) {
            // TODO: use custom type for cudaError_t
            return (int64_t) cudaEventSynchronize(* event);
        }
    );


    m.def(
        "cudaFree",
        [](void * dev_ptr) {
            // TODO: use custom type for cudaError_t
            return (int64_t) cudaFree(dev_ptr);
        }
    );


    m.def(
        "cudaFreeHost",
        [](void * ptr) {
            // TODO: use custom type for cudaError_t
            return (int64_t) cudaFreeHost(ptr);
        }
    );


    m.def(
        "cudaGetDevice",
        [](ptr_wrapper<int> device) {
            // TODO: use custom type for cudaError_t
            return (int64_t) cudaGetDevice(device.get());
        }
    );


    m.def(
        "cudaGetErrorName",
        [](ptr_wrapper<cudaError_t> error) {
            return std::string(cudaGetErrorName(* error));
        }
    );


    m.def(
        "cudaGetErrorString",
        [](ptr_wrapper<cudaError_t> error) {
            return std::string(cudaGetErrorString(* error));
        }
    );


    m.def(
        "cudaGetLastError",
        []() {
            // TODO: use custom type for cudaError_t
            return (int64_t) cudaGetLastError();
        }
    );


    // TODO: Template the argument data type
    m.def(
        "cudaMalloc",
        [](ptr_wrapper<int *> dev_ptr, uint64_t size) {
            // TODO: use custom type for cudaError_t
            return (int64_t) cudaMalloc(dev_ptr.get(), size*sizeof(int));
        }
    );

    m.def(
        "cudaMalloc",
        [](ptr_wrapper<double *> dev_ptr, uint64_t size) {
            // TODO: use custom type for cudaError_t
            return (int64_t) cudaMalloc(dev_ptr.get(), size*sizeof(double));
        }
    );


    // TODO: Template the argument data type
    m.def(
        "cudaMallocHost",
        [](ptr_wrapper<int *> dev_ptr, uint64_t size) {
            // TODO: use custom type for cudaError_t
            return (int64_t) cudaMallocHost(dev_ptr.get(), size*sizeof(int));
        }
    );

    m.def(
        "cudaMallocHost",
        [](ptr_wrapper<double *> dev_ptr, uint64_t size) {
            // TODO: use custom type for cudaError_t
            return (int64_t) cudaMallocHost(dev_ptr.get(), size*sizeof(double));
        }
    );

// //  __host__ ​cudaError_t cudaMemcpy ( void* dst, const void* src, size_t count, cudaMemcpyKind kind ) 
// cudaMemcpyDeviceToHost
// cudaMemcpyHostToDevice
// 
//     // TODO: Template the argument data type to direct data
//     // using custom argument type
//     m.def(
//         "cudaMemcpyDeviceToHost",
//         [](ptr_wrapper<int> dst, ptr_wrapper<int> src, uint64_t count) {
//             // TODO: use custom type for cudaError_t
//             return (int64_t) cudaMemcpy();
//         }
//     );
// 
//     m.def(
//         "cudaMallocHost",
//         [](ptr_wrapper<double *> dev_ptr, uint64_t size) {
//             // TODO: use custom type for cudaError_t
//             return (int64_t) cudaMallocHost(dev_ptr.get(), size*sizeof(double));
//         }
//     );




    m.attr("major_version")   = py::int_(0);
    m.attr("minor_version")   = py::int_(1);
    m.attr("release_version") = py::int_(0);

    // Let the user know that this backend has been compiled _with_ CUDA support
    m.attr("cuda_enabled")            = py::bool_(true);
}
