#ifndef DEVICE_ARRAY_H
#define DEVICE_ARRAY_H

// #include <iostream>
#include <vector>
#include <numeric>
#include <ptr_wrapper.h>
#include <cuda_hip_wrapper.h>
#include <pybind11/pybind11.h>

#include <error.h>
#include <event.h>
#include <data_type.h>


namespace py = pybind11;


template<class T>
class DeviceArray {
    public:

        DeviceArray() = delete;
        DeviceArray(const DeviceArray &) = delete;
        DeviceArray(DeviceArray && o)
        : m_size(o.m_size),
          m_shape(o.m_shape),
          m_ndim(o.m_ndim),
          m_strides(o.m_strides),
          host_ptr(o.host_ptr),
          device_ptr(o.device_ptr),
          device_allocated(o.device_allocated),
          host_allocated(o.host_allocated)
        {
            // Stop destructor (on other object) from freeing pointed memory
            // that has just been moved to this instance
            o.host_allocated = false;
            o.device_allocated = false;
        }

        DeviceArray(ssize_t size)
        : m_size(size), m_shape{size}, device_allocated(false) {
            // define array strides
            m_ndim = 1;
            m_strides = std::vector<ssize_t>(1);
            m_strides[0] = sizeof(T);
            // allocate data
            host_ptr = new T[size];
            // allocation status
            host_allocated = true;
            device_allocated = false;
        };

        DeviceArray(T * data_ptr, ssize_t size)
        : m_size(size), m_shape{size}, device_allocated(false) {
            // define array strides
            m_ndim = 1;
            m_strides = std::vector<ssize_t>(1);
            m_strides[0] = sizeof(T);
            // transfer data
            host_ptr = data_ptr;
            // allocation status
            host_allocated = false;
            device_allocated = false;
        };

        DeviceArray(std::vector<ssize_t> & shape)
        : m_shape{shape}, device_allocated(false) {
            // total size
            m_size = std::accumulate(
                shape.begin(), shape.end(), 1,
                std::multiplies<ssize_t>()
            );
            // define array strides, assuming c-order
            m_ndim = shape.size();
            m_strides = std::vector<ssize_t>(m_ndim);
            ssize_t stride = sizeof(T);
            for (int i = m_ndim - 1; i >= 0; i--) {
                m_strides[i] = stride;
                stride = stride * shape[i];
            }
            // allocate data
            host_ptr = new T[m_size];
            // allocation status
            host_allocated = true;
            device_allocated = false;
        };

        DeviceArray(T * data_ptr, std::vector<ssize_t> & shape)
        : m_shape{shape}, device_allocated(false) {
            // total size
            m_size = std::accumulate(
                shape.begin(), shape.end(), 1,
                std::multiplies<ssize_t>()
            );
            // define array strides, assuming c-order
            m_ndim = shape.size();
            m_strides = std::vector<ssize_t>(m_ndim);
            ssize_t stride = sizeof(T);
            for (int i = m_ndim - 1; i >= 0; i--) {
                m_strides[i] = stride;
                stride = stride * shape[i];
            }
            // transfer data
            host_ptr = data_ptr;
            // allocation status
            host_allocated = false;
            device_allocated = false;
        };

        ~DeviceArray() {
            if (host_allocated)
                delete host_ptr;

            if (device_allocated)
                status = cudaFree(device_ptr);
        }

        void allocate() {
            if (device_allocated) return;

            status = cudaMalloc(& device_ptr, m_size*sizeof(T));
            device_allocated = true;
        }

        void to_device() {
            if (!device_allocated) return;

            status = cudaMemcpy(
                device_ptr, host_ptr, m_size*sizeof(T), cudaMemcpyHostToDevice
            );
        }

        void to_host() {
            if (!device_allocated) return;

            status = cudaMemcpy(
                host_ptr, device_ptr, m_size*sizeof(T), cudaMemcpyDeviceToHost
            );
        }

        T * host_data() { return host_ptr; }
        T * device_data() { return device_ptr; }
        ssize_t size() const { return m_size; }
        const std::vector<ssize_t> & shape() const { return m_shape; };
        const std::vector<ssize_t> & strides() const { return m_strides; };
        cudaError_t last_status() const { return status; }
        bool allocated() const { return device_allocated; }

        py::buffer_info buffer_info() {
            return py::buffer_info(
                /* Pointer to buffer */
                host_ptr,
                /* Size of one scalar */
                sizeof(T),
                /* Python struct-style format descriptor */
                py::format_descriptor<T>::format(),
                /* Number of dimensions */
                m_ndim,
                /* Buffer dimensions */
                m_shape,
                /* Strides (in bytes) for each index */
                m_strides
            );
        }

    private:
        ssize_t m_size;
        std::vector<ssize_t> m_shape;
        int m_ndim;
        std::vector<ssize_t> m_strides;

        T * host_ptr;
        T * device_ptr;

        bool device_allocated;
        bool host_allocated;

        cudaError_t status;
};


template <template <size_t> class SpecT, size_t ... DataIdx>
void generate_device_array(py::module & _mod, std::index_sequence<DataIdx ...>) {
    FOLD_EXPRESSION(
        py::class_<DeviceArray<typename SpecT<DataIdx>::type>>(
            _mod, ("DeviceArray_" + SpecT<DataIdx>::label()).c_str(),
            py::buffer_protocol()
        )
        .def(py::init<size_t>())
        .def(py::init(
            [](py::list l) {
                using dtype = typename SpecT<DataIdx>::type;
                std::vector<ssize_t> shape(py::len(l));
                for (size_t i = 0; i < shape.size(); i++) {
                    shape[i] = l[i].cast<ssize_t>();
                }
                return DeviceArray<dtype>(shape);
            }
        ), py::return_value_policy::reference)
        .def(py::init(
            [](ptr_wrapper<typename SpecT<DataIdx>::type> & a, py::list l) {
                using dtype = typename SpecT<DataIdx>::type;
                std::vector<ssize_t> shape(py::len(l));
                for (size_t i = 0; i < shape.size(); i++) {
                    shape[i] = l[i].cast<ssize_t>();
                }
                return DeviceArray<dtype>(a.get(), shape);
            }
        ), py::return_value_policy::reference)
        .def(py::init(
            [](py::buffer b) {
                py::buffer_info info = b.request();
                using dtype = typename SpecT<DataIdx>::type;
                return DeviceArray<dtype>(
                    static_cast<dtype *>(info.ptr), info.shape
                );
            }
        ), py::return_value_policy::reference)
        .def_buffer(
            [](DeviceArray<typename SpecT<DataIdx>::type> & m) {
                return m.buffer_info();
        })
        .def("size",
            & DeviceArray<typename SpecT<DataIdx>::type>::size
        )
        .def("shape",
            & DeviceArray<typename SpecT<DataIdx>::type>::shape
        )
        .def("strides",
            & DeviceArray<typename SpecT<DataIdx>::type>::strides
        )
        .def("last_status",
            [](const DeviceArray<typename SpecT<DataIdx>::type> & a) {
                return CudaError(a.last_status());
            }
        )
        .def("allocate",
            & DeviceArray<typename SpecT<DataIdx>::type>::allocate
        )
        .def("to_host",
            & DeviceArray<typename SpecT<DataIdx>::type>::to_host
        )
        .def("to_device",
            & DeviceArray<typename SpecT<DataIdx>::type>::to_device
        )
        .def("host_data", 
            [](DeviceArray<typename SpecT<DataIdx>::type> & a) {
                using dtype = typename SpecT<DataIdx>::type;
                return ptr_wrapper<dtype>(a.host_data(), true);
            }
        )
        .def("device_data",
            [](DeviceArray<typename SpecT<DataIdx>::type> & a) {
                using dtype = typename SpecT<DataIdx>::type;
                return ptr_wrapper<dtype>(a.device_data(), false);
            }
        )
        .def("allocated",
            & DeviceArray<typename SpecT<DataIdx>::type>::allocated
        )
    );
}


void generate_device_array(py::module & _mod);

#endif